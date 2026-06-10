#!/usr/bin/env bash
# In-container driver for the PyTorch HotSwap model E2E.
#
# Dispatched from .github/workflows/pytorch-e2e.yml via:
#   srun --container-image=<pytorch-runner.sqsh> --container-writable \
#        --container-remap-root \
#        --container-mounts=<models>,<cache>,<output>,<ci-configs> \
#        bash .github/workflows/scripts/pytorch-e2e.sh
#
# Runs each requested model's compare-mode E2E (local vs hotswap-rewritten
# + teacher-forced equivalence) inside the frozen pytorch-runner image and
# leaves summary.{json,md} under /output/<model>/latest/ for the workflow's
# summary step to render to $GITHUB_STEP_SUMMARY.
#
# Required env (exported by the workflow before srun, inherited via --export=ALL):
#   MODELS        space-separated config stems, e.g. "phi4_mini sd_3_5_large"
# Optional env:
#   TARGET_GFX               GPU ISA to transpile to (default gfx950). The
#                            model JSON hardcodes gfx950; if this differs we
#                            sed the JSON (there is no env hook for target_gfx).
#   PYTORCH_TIMEOUT_SECONDS  per-workload cap (default 3600; cold transpile of
#                            all GEMM kernels exceeds the harness's 900s default)
#   CACHE_DIR                persistent HotSwap translation cache (default /cache)
set -uxo pipefail

: "${MODELS:?must be set (space-separated model config stems)}"
TARGET_GFX="${TARGET_GFX:-gfx950}"
CACHE_DIR="${CACHE_DIR:-/cache}"
export PYTORCH_TIMEOUT_SECONDS="${PYTORCH_TIMEOUT_SECONDS:-3600}"

REPO=/home/hotswap/rocm-hotswap-testing
CFG="$REPO/data/pytorch/models"

echo "=== GPU host: $(hostname) ==="
rocminfo 2>/dev/null | grep -E "Name:\s+gfx" | head -1 || true

# --- Harness source overlay -------------------------------------------------
# Refresh the harness SOURCE (scripts/data/runtime/Makefile) from a pinned
# rocm-hotswap-testing checkout bind-mounted read-only at /harness. This is
# the going-forward model: the image carries only the heavy frozen runtime
# (deps/venvs/comgr/libhsa/intercept); the lightweight source comes from a
# git checkout, so harness + config changes are a `git pull`, not an image
# rebuild. The container is --container-writable so these copies are
# ephemeral (the sqsh is never modified). The scripts compute REPO_ROOT from
# their own location at runtime, so no host->container path rewrite is needed
# (the only host-pathed file, deps/pytorch-env.config.sh, is NOT overlaid).
if [ -d /harness ]; then
  # Only the lightweight code dirs (scripts ~360K, runtime ~390K). NOT data/
  # (~1.5G of fixtures) -- the model configs we need come from /ci-configs
  # below, and the baked image already carries the rest of data/.
  # --preserve=mode keeps exec bits without chown/xattr (which fail with
  # "operation not supported" across the read-only bind-mount / NFS).
  for d in scripts runtime; do
    [ -d "/harness/$d" ] && cp -r --preserve=mode "/harness/$d/." "$REPO/$d/"
  done
  [ -f /harness/Makefile ] && cp --preserve=mode /harness/Makefile "$REPO/Makefile"
fi
# Back-compat / standalone: configs-only overlay (e.g. the conductor docker
# test mounts just the model configs at /ci-configs).
if [ -d /ci-configs ]; then
  cp -v /ci-configs/*.json "$CFG"/ 2>/dev/null || true
  cp -v /ci-configs/*.prompts.json "$CFG"/ 2>/dev/null || true
fi

# --- comgr-under-test injection --------------------------------------------
# By default the e2e uses the comgr baked into the image. For per-commit
# llvm-project CI we want to test the PR's freshly-built libamd_comgr.so.
# deps/pytorch-env.config.sh hard-`export`s PYTORCH_COMGR_RUNTIME, so a plain
# env var won't win; rewrite that one generated line in-place (writable,
# ephemeral container).
if [ -n "${COMGR_RUNTIME:-}" ]; then
  envcfg="$REPO/deps/pytorch-env.config.sh"
  sed -i "s|^export PYTORCH_COMGR_RUNTIME=.*|export PYTORCH_COMGR_RUNTIME=\"$COMGR_RUNTIME\"|" "$envcfg"
  echo "injected comgr-under-test: $COMGR_RUNTIME"
fi
# The transpiler shells out to llc/llvm-mc/ld.lld. Point it at the PR build's
# tools if provided (overrides the path baked into libamd_comgr at compile time).
if [ -n "${COMGR_TOOLS_DIR:-}" ]; then
  export HOTSWAP_TRANSPILER_LLVM_TOOLS_DIR="$COMGR_TOOLS_DIR"
  echo "injected transpiler tools dir: $COMGR_TOOLS_DIR"
fi

# The GPU is renumbered to index 0 inside a --gres=gpu:1 allocation
# (ROCR_VISIBLE_DEVICES=0); the harness otherwise inherits the physical
# index and hits hipErrorNoDevice.
export PYTORCH_GPU=0
# Point the translation cache at the bind-mounted persistent dir; the image
# bakes an in-container (ephemeral) path, so without this every kernel is a
# cold transpile and results vanish when srun ends.
export HSA_HOTSWAP_CACHE_DIR="$CACHE_DIR"

# Stream the high-signal progress from a model's per-branch run.log files to
# stdout (the GH Actions console) while run-model works. The harness redirects
# branch output to run.log and emits little to stdout, so without this the CI
# step looks frozen for the whole multi-minute transpile. We drop the millions
# of ':3:'/':4:' HIP + rocBLAS trace lines (those stay in run.log) and stream
# the rest: transpiler decisions, proof, token generation, errors.
# Sets TAILER_PID. The background subshell inherits this script's stdout (so
# lines stream live to the GH Actions console); do NOT capture it via $(...),
# which would swallow the output and can hang the command substitution.
TAILER_PID=""
start_log_stream() {
  local scratch="$1"
  (
    local lr="" rd=""
    for _ in $(seq 1 240); do
      lr=$(find "$scratch" -path "*/local/run.log" 2>/dev/null | head -1)
      [ -n "$lr" ] && break
      sleep 1
    done
    [ -z "$lr" ] && exit 0
    rd=$(dirname "$(dirname "$lr")")
    # -F retries hotswap/run.log until run-model creates it.
    stdbuf -oL tail -n +1 -F "$rd/local/run.log" "$rd/hotswap/run.log" 2>/dev/null \
      | grep --line-buffered -vE '^:[0-9]+:' \
      | sed -u 's/^/    | /'
  ) &
  TAILER_PID=$!
}

overall_rc=0
for m in $MODELS; do
  cfg="$CFG/$m.json"
  mkdir -p "/output/$m"

  # A model with no config (a group whose workload module doesn't exist yet)
  # or whose weights aren't staged is reported as PENDING, not failed -- the
  # suite lists one representative per model-support-plan group so the summary
  # shows the whole landscape, including groups we can't run yet.
  if [ ! -f "$cfg" ]; then
    echo "::notice::$m pending -- no config (workload/group not wired yet)"
    echo "no config" > "/output/$m/PENDING"
    continue
  fi
  mp=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('default_model_path',''))" "$cfg" 2>/dev/null)
  if [ -z "$mp" ] || [ ! -e "$mp" ]; then
    echo "::notice::$m pending -- weights not staged ($mp)"
    echo "no weights: ${mp:-<unset>}" > "/output/$m/PENDING"
    continue
  fi

  # target_gfx is read from the JSON (no env override). Default config is
  # gfx950; rewrite only if a different ISA was requested (e.g. gfx942).
  if [ "$TARGET_GFX" != "gfx950" ]; then
    sed -i "s/\"target_gfx\": \"gfx950\"/\"target_gfx\": \"$TARGET_GFX\"/" "$cfg"
  fi

  echo "::group::run-model $m (target_gfx=$TARGET_GFX)"
  start_log_stream "/output/$m"
  run-model "$m" || echo "::warning::run-model $m exited non-zero (harness exits non-zero on expected equivalence divergence; CI gate is evaluated from summary.json below)"
  [ -n "$TAILER_PID" ] && { kill "$TAILER_PID" 2>/dev/null || true; wait "$TAILER_PID" 2>/dev/null || true; }
  sm=$(find "/output/$m" -name summary.md 2>/dev/null | head -1)
  if [ -n "$sm" ]; then echo "----- summary.md ($m) -----"; cat "$sm"; fi

  # CI gate from the summary, NOT run-model's exit code: the harness exits
  # non-zero when equivalence diverges, but divergence is EXPECTED
  # (accumulation-order token flips). The gate is: baseline ran AND the
  # gfx1250->target transpile ran the model end-to-end with no transpile
  # failures (local.passed && hotswap.passed && hotswap_fail==0).
  sj=$(find "/output/$m" -name summary.json 2>/dev/null | head -1)
  if [ -z "$sj" ]; then
    echo "::error::$m produced no summary.json"; overall_rc=1
  elif ! python3 - "$sj" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
l = s.get("local", {}) or {}; h = s.get("hotswap", {}) or {}
ok = (l.get("passed") is True) and (h.get("passed") is True) \
     and (int(h.get("hotswap_fail", 0) or 0) == 0)
sys.exit(0 if ok else 1)
PY
  then
    echo "::error::$m gate failed (baseline or transpile did not complete cleanly)"; overall_rc=1
  else
    echo "$m: gate PASS (transpile pipeline healthy; equivalence verdict shown above)"
  fi
  echo "::endgroup::"
done

exit "$overall_rc"
