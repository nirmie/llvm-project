#!/usr/bin/env bash
# In-container driver for the SGLang HotSwap E2E (sibling of pytorch-e2e.sh).
#
# DRAFT / UNVALIDATED: the sglang-runner image isn't built yet (sglang pins
# torch==2.9.1 vs the base ROCm torch 2.12 -- see rep_hotswap/sglang-runner
# Dockerfile notes). This runs only when the combined workflow is dispatched
# with sglang_ready=true. Validate end-to-end on a GPU before trusting it.
#
# Env (via --export=ALL):
#   SGLANG_PROFILES  space-separated profiles, e.g. "llama phi4_mini"
#   TARGET_GFX       gfx950 (default) | gfx942
#   CACHE_DIR        persistent translation cache (default /cache)
set -uxo pipefail

: "${SGLANG_PROFILES:?must be set}"
TARGET_GFX="${TARGET_GFX:-gfx950}"
CACHE_DIR="${CACHE_DIR:-/cache}"
REPO=/home/hotswap/rocm-hotswap-testing

# Harness source overlay (scripts/runtime/Makefile), same as pytorch-e2e.sh.
if [ -d /harness ]; then
  for d in scripts runtime; do
    [ -d "/harness/$d" ] && cp -r --preserve=mode "/harness/$d/." "$REPO/$d/"
  done
  [ -f /harness/Makefile ] && cp --preserve=mode /harness/Makefile "$REPO/Makefile"
fi

export HSA_HOTSWAP_CACHE_DIR="$CACHE_DIR"
export SGLANG_TARGET_GFX="$TARGET_GFX"
export SGLANG_GPU=0
# Teacher-forced is a diagnostic cross-check we don't gate on; skip it (avoids
# the MXFP4->BF16 decompose OOM on gpt_oss and saves time). Gate = equivalence.
export SGLANG_SKIP_TEACHER_FORCED=1

overall_rc=0
for p in $SGLANG_PROFILES; do
  # run-sglang-model resolves SGLANG_MODEL_PATH from /mnt/gfx_apps/models/<profile>
  # by default; point it at the staged /projects weights instead. The llama
  # profile maps to Llama-3.1-8B-Instruct; phi4_mini reuses the Phi-4 weights.
  case "$p" in
    llama)     export SGLANG_MODEL_PATH=/projects/hotswap-ci/models/meta-llama/Llama-3.1-8B-Instruct ;;
    phi4_mini) export SGLANG_MODEL_PATH=/projects/hotswap-ci/models/microsoft/Phi-4-mini-instruct ;;
    *)         export SGLANG_MODEL_PATH="/projects/hotswap-ci/models/$p" ;;
  esac
  if [ ! -e "$SGLANG_MODEL_PATH" ]; then
    echo "no weights: $SGLANG_MODEL_PATH" > "/output/$p/PENDING"; mkdir -p "/output/$p"; continue
  fi
  export SGLANG_SCRATCH_ROOT="/output/$p"
  mkdir -p "$SGLANG_SCRATCH_ROOT"
  echo "::group::run-sglang-model $p (target_gfx=$TARGET_GFX)"
  run-sglang-model "$p" || echo "::warning::run-sglang-model $p exited non-zero (gate evaluated from summary.json)"
  # The baked /opt/sglang-repro/run_sglang_e2e.sh HARDCODES its scratch to
  # /opt/sglang-repro/scratch (it overwrites SGLANG_SCRATCH_ROOT), which lives in
  # the ephemeral container -- the gate + host renderer can't see it. Copy the
  # produced run into the bind-mounted /output/$p so summary.{json,md} are
  # captured. (Proper fix: make the baked script honor SGLANG_SCRATCH_ROOT; image rebuild.)
  if [ -d /opt/sglang-repro/scratch ]; then
    cp -r --no-preserve=mode /opt/sglang-repro/scratch/. "/output/$p/" 2>/dev/null || true
  fi
  # Gate = the transpile pipeline ran end-to-end (a verdict was produced).
  # `diverged` is the EXPECTED gfx1250->gfx950 accumulation effect, reported not
  # failed (matches the pytorch gate). Fail only on no summary or no verdict.
  sj=$(find "/output/$p" -name summary.json 2>/dev/null | head -1)
  if [ -z "$sj" ]; then
    echo "::error::$p produced no summary.json"; overall_rc=1
  elif ! python3 -c "import json,sys; s=json.load(open(sys.argv[1])); st=(s.get('equivalence',{}) or {}).get('overall_status'); sys.exit(0 if st in ('equivalent','numerically_close','distributionally_equivalent','diverged') else 1)" "$sj"; then
    echo "::error::$p gate failed (no valid equivalence verdict -> transpile did not complete)"; overall_rc=1
  fi
  echo "::endgroup::"
done
exit "$overall_rc"
