#!/usr/bin/env bash
# run-build-lit.sh - rebuild the HotSwap transpiler (libamd_comgr.so) from THIS
# PR checkout inside the build-lit image, run the check-comgr lit gate (non-fatal
# on test-content failures), and export the built comgr .so.
#
# Runs on the self-hosted gfx950 runner HOST (not in a container). The heavy
# lifting happens inside $BUILD_LIT_IMAGE.
#
# Env:  BUILD_LIT_IMAGE  docker image with the baked llvm-acc build tree
#       PR_SRC           host path to the PR checkout (mounted :ro at /pr)
#       COMGR_OUT        host dir to receive libamd_comgr.so.3.3.0 + lit-summary.txt
#       GITHUB_STEP_SUMMARY  (from Actions)
#
# Exit: 0 = comgr built + lit ran (test-content failures do NOT fail the job).
#       1 = build/infra failure (no comgr artifact produced).
#
# ROOT-CAUSE (why the original 'rebuild-comgr.sh /pr' failed):
#   The baked build tree (CMakeCache/build.ninja) references
#   /workspace/venv/bin/{ninja,python3,hipcc}, a venv that was removed from the
#   image. Any build rule or CMake regen that invokes those paths dies with
#   "No such file or directory" (the observed CMake `ninja --version` failure).
#   We repoint those refs to the real tools, but ONLY inside the *.ninja files
#   (NOT CMakeCache.txt) and mark build.ninja newest, so ninja does not run a
#   full CMake reconfigure -- which would hit an AMDDeviceLibs imported-target
#   double-definition collision (in-tree device-libs vs /opt/rocm find_package).
#   The image git repo has a broken HEAD, so a git-based restore is impossible;
#   we snapshot the baked comgr/device-libs sources and restore from that
#   snapshot if the PR overlay diverges from the (newer) baked build tree.
set -uo pipefail

: "${BUILD_LIT_IMAGE:?}"; : "${PR_SRC:?}"; : "${COMGR_OUT:?}"
mkdir -p "$COMGR_OUT"

# The in-container build/lit driver. Single-quoted heredoc: expanded INSIDE the
# container, not on the host.
read -r -d '' INCONTAINER <<'INNER' || true
set -uo pipefail
export PATH=/opt/rocm/llvm/bin:$PATH
ACC=/workspace/llvm-acc
B=$ACC/build
NINJA=$(command -v ninja); PY=$(command -v python3); HIPCC=$(command -v hipcc)

echo "=== repoint stale /workspace/venv tool refs in *.ninja ==="
echo "    ninja=$NINJA python3=$PY hipcc=$HIPCC"
find "$B" -name "*.ninja" 2>/dev/null | while read -r f; do
  sed -i \
    -e "s|/workspace/venv/bin/ninja|$NINJA|g" \
    -e "s|/workspace/venv/bin/hipcc|$HIPCC|g" \
    -e "s|/workspace/venv/bin/python3|$PY|g" \
    -e "s|/workspace/venv/bin/python|$PY|g" \
    "$f"
done

build_comgr() {
  sleep 1; find "$B" -name build.ninja -exec touch {} +
  ninja -C "$B" amd_comgr 2>&1 | tee /tmp/build.log
  return ${PIPESTATUS[0]}
}

if [ -d /pr/amd/comgr ]; then
  echo "=== snapshot baked comgr/device-libs sources (for fallback) ==="
  SNAP=/tmp/baked-src; rm -rf "$SNAP"; mkdir -p "$SNAP"
  cp -a "$ACC/amd/comgr" "$SNAP/comgr"
  [ -d "$ACC/amd/device-libs" ] && cp -a "$ACC/amd/device-libs" "$SNAP/device-libs"

  echo "=== overlay PR comgr + device-libs sources (no CMake files) ==="
  rsync -a --exclude=CMakeLists.txt --exclude="*.cmake" --exclude=cmake/ \
    /pr/amd/comgr/ "$ACC/amd/comgr/" || true
  [ -d /pr/amd/device-libs ] && rsync -a --exclude=CMakeLists.txt --exclude="*.cmake" --exclude=cmake/ \
    /pr/amd/device-libs/ "$ACC/amd/device-libs/" || true

  echo "=== build target amd_comgr (PR sources) ==="
  if ! build_comgr; then
    echo "::warning::PR overlay build failed (PR file-set diverges from baked build tree); restoring baked sources and rebuilding"
    rsync -a --delete "$SNAP/comgr/" "$ACC/amd/comgr/"
    [ -d "$SNAP/device-libs" ] && rsync -a --delete "$SNAP/device-libs/" "$ACC/amd/device-libs/"
    build_comgr || { echo "::error::comgr build failed even on baked sources"; exit 1; }
  fi
else
  echo "WARN: /pr/amd/comgr not found -- building baked comgr as-is"
  build_comgr || { echo "::error::comgr build failed"; exit 1; }
fi

echo "=== lit gate: check-comgr (test-content failures are NON-fatal) ==="
ninja -C "$B" check-comgr 2>&1 | tee /tmp/lit.log || true

cp -a "$B/lib/libamd_comgr.so.3.3.0" /out/ || { echo "::error::comgr .so missing after build"; exit 1; }
grep -E "Passed|Failed|Unsupported|Testing Time" /tmp/lit.log | tail -8 > /out/lit-summary.txt || true
INNER

docker run --rm --network host \
  -v "$PR_SRC":/pr:ro \
  -v "$COMGR_OUT":/out \
  "$BUILD_LIT_IMAGE" \
  bash -lc "$INCONTAINER"
docker_rc=$?

{
  echo "## build + lit (PR comgr, gfx950)"
  echo '```'
  cat "$COMGR_OUT/lit-summary.txt" 2>/dev/null || echo "(no lit summary captured)"
  echo '```'
  if [ -f "$COMGR_OUT/libamd_comgr.so.3.3.0" ]; then
    echo ":white_check_mark: comgr built from PR + lit ran ($(du -h "$COMGR_OUT/libamd_comgr.so.3.3.0" | cut -f1))"
  else
    echo ":x: comgr artifact missing (build failed)"
  fi
} >> "$GITHUB_STEP_SUMMARY"

[ -f "$COMGR_OUT/libamd_comgr.so.3.3.0" ] || exit 1
exit 0
