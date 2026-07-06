#!/usr/bin/env bash
# Run one HotSwap PyTorch-path model e2e compare (local gfx950 vs hotswap
# gfx1250->target) inside the PR#10 image, then evaluate the gate. Used by
# docker-e2e-pytorch-gfx950.yml. Runs on the self-hosted runner HOST.
#
# Args:   $1 NAME     leg name (= config stem, e.g. whisper_small)
#         $2 SUBPATH  model dir under $WEIGHTS_HOST (e.g. openai/whisper-small)
# Env:    IMAGE         PR#10 image with the pytorch hotswap stack
#         WEIGHTS_HOST  host dir mounted at /data (model is /data/$SUBPATH)
#         SCRATCH_BASE  host dir for per-model scratch
#         GPU           GPU index (e.g. 7)
#         GITHUB_STEP_SUMMARY, GITHUB_WORKSPACE  (from Actions)
#
# Exit: 0 = gate PASS or weights-absent (skipped); 1 = gate FAIL or run error.
# NOTE: invoke with a shell WITHOUT errexit (find over the root-owned scratch
# dir exits non-zero on permission-denied subpaths).
set -uo pipefail

NAME="$1"; SUBPATH="$2"
HOSTPATH="$WEIGHTS_HOST/$SUBPATH"
SCRATCH="$SCRATCH_BASE/$NAME"
GATE="$GITHUB_WORKSPACE/.github/workflows/scripts/gate-pytorch.py"

hdr() { echo "## $NAME (pytorch, gfx950)" >> "$GITHUB_STEP_SUMMARY"; echo >> "$GITHUB_STEP_SUMMARY"; }

if [ ! -e "$HOSTPATH" ]; then
  hdr
  echo ":fast_forward: SKIPPED — weights not present at \`$HOSTPATH\`" >> "$GITHUB_STEP_SUMMARY"
  echo "SKIPPED (no weights: $HOSTPATH)"
  exit 0
fi

rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
# Optional: mount PR-built comgr over the image comgr (set by the gated
# pipeline via download-artifact). Unset/missing -> use image-baked comgr.
PR_COMGR_MNT=()
if [ -n "${PR_COMGR:-}" ] && [ -f "$PR_COMGR" ]; then
  echo "Using PR-built comgr: $PR_COMGR"
  PR_COMGR_MNT=(-v "$PR_COMGR":/workspace/llvm-acc/build/lib/libamd_comgr.so.3.3.0:ro)
else
  echo "PR_COMGR not provided -- using image-baked comgr"
fi
docker run --rm \
  --device=/dev/kfd --device=/dev/dri \
  --group-add 44 --group-add 109 \
  --ipc=host --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined --security-opt label=disable \
  --network=host \
  -v "$WEIGHTS_HOST":/data:ro \
  -v "$SCRATCH":/scratch \
  "${PR_COMGR_MNT[@]}" \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    cd /workspace/rocm-hotswap-testing
    export LD_LIBRARY_PATH=/workspace/llvm-acc/build/lib:$LD_LIBRARY_PATH
    make pytorch-hotswap-model-e2e \
      PYTORCH_MODEL_CONFIG=data/pytorch/models/'"$NAME"'.json \
      PYTORCH_MODEL_PATH=/data/'"$SUBPATH"' \
      PYTORCH_PYTHON=/workspace/venv/bin/python \
      PYTORCH_LIBHSA_RUNTIME=/workspace/rocm-systems/projects/rocr-runtime/build/rocr/lib/libhsa-runtime64.so \
      PYTORCH_INTERCEPT_LIB=/workspace/rocm-hotswap-testing/build/libhotswap_intercept.so \
      PYTORCH_GFX_OVERRIDE_LIB=/workspace/rocm-hotswap-testing/build/libhip_device_gfx_override.so \
      PYTORCH_COMGR_RUNTIME=/workspace/llvm-acc/build/lib/libamd_comgr.so.3.3.0 \
      PYTORCH_ROCBLAS_TENSILE_LIBPATH=/workspace/rocm-hotswap-testing/data/kernels/gfx1250_b0/tensile \
      PYTORCH_SCRATCH_ROOT=/scratch \
      PYTORCH_GPU='"$GPU"'
  ' 2>&1 | tee "$SCRATCH/run.log"
docker_rc=${PIPESTATUS[0]}

dump_failing_logs() {
  echo "::error::$NAME (pytorch gfx950) FAILED — full per-run logs below"
  local logs f rel
  logs=$(find "$SCRATCH" -name run.log -path '*/run*/*' 2>/dev/null | sort)
  [ -z "$logs" ] && logs=$(find "$SCRATCH" -name run.log 2>/dev/null | sort)
  [ -z "$logs" ] && { echo "::warning::no per-run run.log under $SCRATCH"; return; }
  for f in $logs; do
    rel="${f#$SCRATCH/}"
    echo "::group::run.log — $rel"; cat "$f" 2>/dev/null || echo "(unreadable)"; echo "::endgroup::"
  done
}

hdr
SJ=$(find "$SCRATCH" -name summary.json 2>/dev/null | sort | tail -1 || true)
# The pytorch harness exits non-zero on expected equivalence divergence, but
# still writes summary.json. So the gate is evaluated from summary.json, NOT the
# make exit code; only treat a MISSING summary as a hard failure (crashed before
# completion).
if [ -z "$SJ" ]; then
  {
    echo ":x: run FAILED — no summary.json (make exit=$docker_rc; crashed before writing)"
    echo "Full per-run logs are in the step output (collapsible \`run.log\` groups)."
  } >> "$GITHUB_STEP_SUMMARY"
  dump_failing_logs
  exit 1
fi

VERDICT=$(python3 "$GATE" "$SJ"); rc=$?
IFS='|' read -r ok rest <<< "$VERDICT"
{
  echo '```'
  echo "${VERDICT//|/$'\n'}"
  echo '```'
  if [ "$rc" = "0" ]; then
    echo ":white_check_mark: gate PASSED (HotSwap transpile pipeline healthy)"
    echo "$VERDICT" | grep -q "equiv_passed=True" || echo "> note: numerical equivalence drifted (see equiv=) — not gated."
  else
    echo ":x: gate FAILED — native or hotswap branch did not complete cleanly"
  fi
} >> "$GITHUB_STEP_SUMMARY"
[ "$rc" = "0" ] || dump_failing_logs
exit $rc
