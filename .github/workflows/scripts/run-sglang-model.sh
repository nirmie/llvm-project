#!/usr/bin/env bash
# Run one SGLang HotSwap compare for a single model inside the prebuilt image,
# then evaluate the equivalence gate. Shared by docker-e2e-gfx942.yml and
# docker-e2e-gfx950.yml. Runs on the self-hosted runner HOST (not in a container).
#
# Args:   $1 PROFILE   harness sglang profile (e.g. gemma3_4b_it)
#         $2 SUBPATH    model dir under $WEIGHTS_HOST (e.g. google/gemma-3-4b-it)
# Env:    IMAGE         docker image with the harness + hotswap stack
#         WEIGHTS_HOST  host dir mounted at /data (model is /data/$SUBPATH)
#         SCRATCH_BASE  host dir for per-model scratch
#         GPU           GPU index (e.g. 7)
#         TARGET_GFX    gfx942 | gfx950
#         GITHUB_STEP_SUMMARY, GITHUB_WORKSPACE  (from Actions)
#
# Exit: 0 = gate PASS or weights-absent (skipped); 1 = gate FAIL or run error.
# NOTE: invoke with a shell WITHOUT errexit (find over the root-owned scratch
# dir exits non-zero on permission-denied subpaths).
set -uo pipefail

PROFILE="$1"; SUBPATH="$2"
HOSTPATH="$WEIGHTS_HOST/$SUBPATH"
SCRATCH="$SCRATCH_BASE/$PROFILE"
GATE="$GITHUB_WORKSPACE/.github/workflows/scripts/gate-equivalence.py"

hdr() { echo "## $PROFILE ($TARGET_GFX)" >> "$GITHUB_STEP_SUMMARY"; echo >> "$GITHUB_STEP_SUMMARY"; }

if [ ! -e "$HOSTPATH" ]; then
  hdr
  echo ":fast_forward: SKIPPED — weights not present at \`$HOSTPATH\`" >> "$GITHUB_STEP_SUMMARY"
  echo "SKIPPED (no weights: $HOSTPATH)"
  exit 0
fi

rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
docker run --rm \
  --device=/dev/kfd --device=/dev/dri \
  --group-add 44 --group-add 109 \
  --ipc=host --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined --security-opt label=disable \
  --network=host \
  -v "$WEIGHTS_HOST":/data \
  -v "$SCRATCH":/scratch \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    cd /workspace/rocm-hotswap-testing
    export LD_LIBRARY_PATH=/workspace/llvm-acc/build/lib:$LD_LIBRARY_PATH
    make sglang-hotswap-e2e-compare \
      SGLANG_MODEL_PATH=/data/'"$SUBPATH"' \
      SGLANG_PYTHON=/workspace/venv/bin/python \
      SGLANG_PROFILE='"$PROFILE"' \
      SGLANG_LIBHSA_RUNTIME=/workspace/rocm-systems/projects/rocr-runtime/build/rocr/lib/libhsa-runtime64.so \
      SGLANG_INTERCEPT_LIB=/workspace/rocm-hotswap-testing/build/libhotswap_intercept.so \
      SGLANG_SCRATCH_ROOT=/scratch \
      SGLANG_GPU='"$GPU"' \
      SGLANG_TARGET_GFX='"$TARGET_GFX"' \
      SGLANG_SOURCE_TARGET=gfx1250:32
  ' 2>&1 | tee "$SCRATCH/run.log"

hdr
SJ=$(find "$SCRATCH" -name summary.json 2>/dev/null | sort | tail -1 || true)
if [ -z "$SJ" ]; then
  echo ":x: no summary.json (run failed before completion)" >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi
VERDICT=$(python3 "$GATE" "$SJ"); rc=$?
IFS='|' read -r ok status strict <<< "$VERDICT"
{
  echo '```'
  echo "overall_status:        $status"
  echo "equivalence (strict):  $strict"
  echo '```'
  if [ "$rc" = "0" ]; then
    echo ":white_check_mark: gate PASSED (HotSwap transpile produced a valid verdict: \`$status\`)"
    [ "$strict" = "True" ] || echo "> note: strict equivalence did not pass (\`$status\`) — expected gfx1250→target accumulation effect, not gated."
  else
    echo ":x: gate FAILED — no valid equivalence verdict (run did not complete / no transpile)"
  fi
} >> "$GITHUB_STEP_SUMMARY"
exit $rc
