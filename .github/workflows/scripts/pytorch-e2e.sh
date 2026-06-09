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
  for d in scripts data runtime; do
    [ -d "/harness/$d" ] && cp -a "/harness/$d/." "$REPO/$d/"
  done
  [ -f /harness/Makefile ] && cp -a /harness/Makefile "$REPO/Makefile"
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

overall_rc=0
for m in $MODELS; do
  cfg="$CFG/$m.json"
  if [ ! -f "$cfg" ]; then
    echo "::error::no model config $cfg" >&2
    overall_rc=1
    continue
  fi

  # target_gfx is read from the JSON (no env override). Default config is
  # gfx950; rewrite only if a different ISA was requested (e.g. gfx942).
  if [ "$TARGET_GFX" != "gfx950" ]; then
    sed -i "s/\"target_gfx\": \"gfx950\"/\"target_gfx\": \"$TARGET_GFX\"/" "$cfg"
  fi

  echo "=== run-model $m  (target_gfx=$TARGET_GFX) ==="
  run-model "$m" || { rc=$?; echo "::warning::run-model $m exited rc=$rc"; overall_rc=1; }
done

exit "$overall_rc"
