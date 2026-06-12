#!/usr/bin/env bash
# In-container driver for the TRUE-gfx1250 PyTorch HotSwap model E2E.
#
# Counterpart to pytorch-e2e.sh, but for the hotswap-a0-runner image whose
# torch / rocBLAS / HIP are genuinely compiled for gfx1250. There is no native
# gfx950 baseline in that image, so each model runs HOTSWAP-ONLY: the official
# comgr adapter (HSA_TOOLS_LIB=libamd_comgr_hotswap_tool.so) transpiles every
# gfx1250 code object to the running gfx950 device. The container's baked
# `run-model` wrapper arms the adapter and calls run_hotswap_only_gfx1250.sh;
# this script just delivers the harness branch + per-CI model-path overrides and
# evaluates a gfx1250-appropriate gate from summary.json.
#
# Required env (exported by the workflow before srun, inherited via --export=ALL):
#   MODELS        space-separated config stems, e.g. "phi4_mini qwen3_0_6b"
# Optional env:
#   PYTORCH_TIMEOUT_SECONDS  per-workload cap (default 3600)
#   CACHE_DIR                persistent transpile cache (default /cache)
set -uxo pipefail

: "${MODELS:?must be set (space-separated model config stems)}"
CACHE_DIR="${CACHE_DIR:-/cache}"
export HSA_HOTSWAP_CACHE_DIR="$CACHE_DIR"
export PYTORCH_TIMEOUT_SECONDS="${PYTORCH_TIMEOUT_SECONDS:-3600}"

REPO=/home/hotswap/rocm-hotswap-testing
CFG="$REPO/data/pytorch/models"

echo "=== GPU host: $(hostname) ==="
rocminfo 2>/dev/null | grep -E "Name:\s+gfx" | head -1 || true

# --- Harness source overlay (pinned to the gfx1250 branch via HARNESS_REF) ---
# Same model as pytorch-e2e.sh: the image carries the heavy gfx1250 runtime;
# the lightweight harness source comes from the bind-mounted /harness checkout
# so driver/config changes are a git pull, not an image rebuild.
if [ -d /harness ]; then
  for d in scripts runtime validation; do
    [ -d "/harness/$d" ] && cp -r --preserve=mode "/harness/$d/." "$REPO/$d/"
  done
  [ -f /harness/Makefile ] && cp --preserve=mode /harness/Makefile "$REPO/Makefile"
  if [ -d /harness/data/pytorch/models ]; then
    cp /harness/data/pytorch/models/*.json "$CFG"/ 2>/dev/null || true
  fi
fi
# Per-CI override overlay: the model configs' default_model_path is set for the
# Alola model store here (the baked configs point at the conductor's /mnt path).
if [ -d /ci-configs ]; then
  cp -v /ci-configs/*.json "$CFG"/ 2>/dev/null || true
  cp -v /ci-configs/*.prompts.json "$CFG"/ 2>/dev/null || true
fi

overall_rc=0
for m in $MODELS; do
  cfg="$CFG/$m.json"
  mkdir -p "/output/$m"

  if [ ! -f "$cfg" ]; then
    echo "::notice::$m pending -- no config (workload/group not wired yet)"
    echo "no config" > "/output/$m/PENDING"; continue
  fi
  mp=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('default_model_path',''))" "$cfg" 2>/dev/null)
  if [ -z "$mp" ] || [ ! -e "$mp" ]; then
    echo "::notice::$m pending -- weights not staged ($mp)"
    echo "no weights: ${mp:-<unset>}" > "/output/$m/PENDING"; continue
  fi

  echo "::group::run-model $m (true gfx1250 -> gfx950 transpile)"
  # The a0 image's run-model is the hotswap-only/tool wrapper; it writes
  # summary.json to /output/$m. A non-zero exit is EXPECTED when an
  # un-transpilable gfx1250 kernel is forwarded and then dispatched on gfx950
  # (segfault) -- the gate below is read from summary.json, not the exit code.
  PYTORCH_SCRATCH_ROOT="/output/$m" run-model "$m" \
    || echo "::warning::run-model $m exited non-zero (expected on transpile gaps; gate evaluated from summary.json)"
  sm=$(find "/output/$m" -name summary.md 2>/dev/null | head -1)
  if [ -n "$sm" ]; then echo "----- summary.md ($m) -----"; cat "$sm"; fi

  # gfx1250 gate: the run must have produced a summary AND attempted to
  # transpile the gfx1250 code objects. A "clean" pass requires every
  # transpiled CO to lift (transpile_failed==0 and transpile_ok>0). A run that
  # hit transpiler ISA gaps is reported (warning) -- it is the expected signal
  # this sweep exists to surface, not an orchestration failure.
  sj=$(find "/output/$m" -name summary.json 2>/dev/null | head -1)
  if [ -z "$sj" ]; then
    echo "::error::$m produced no summary.json"; overall_rc=1
  else
    verdict=$(python3 - "$sj" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
h = s.get("hotswap", {}) or {}
t = h.get("tool_transpile", {}) or {}
ok = int(t.get("transpile_ok", 0) or 0)
fail = int(t.get("transpile_failed", 0) or 0)
att = int(t.get("co_transpile", 0) or 0)
if att == 0:
    print("no_transpile"); sys.exit()
if fail == 0 and ok > 0 and h.get("passed") is True:
    print("clean")
else:
    print("gaps:" + ",".join(t.get("unsupported_opcodes", []) or []))
PY
)
    case "$verdict" in
      clean) echo "$m: gfx1250 gate PASS (all transpiled CO lifted; model ran)";;
      no_transpile) echo "::warning::$m no gfx1250 code objects were transpiled (unexpected)";;
      gaps:*) echo "::warning::$m transpiler gaps -> ${verdict#gaps:}";;
    esac
  fi
  echo "::endgroup::"
done

exit "$overall_rc"
