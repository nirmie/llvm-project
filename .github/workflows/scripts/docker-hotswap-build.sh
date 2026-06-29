#!/usr/bin/env bash
# Docker variant of the hotswap lit build (no SLURM). Runs INSIDE a
# rocm/pytorch container started by docker-lit.yml. Builds LLVM + comgr
# (hotswap transpile ON) into a persistent bind-mounted build dir and runs
# the Comgr lit suite (check-comgr).
#
# Required env (set by the workflow via docker run -e):
#   GITHUB_WORKSPACE  source tree root (bind-mounted)
#   CCACHE_DIR        persistent ccache dir (bind-mounted, survives runs)
#   BUILD_DIR         persistent ninja build dir (bind-mounted, survives runs)
set -euxo pipefail

: "${GITHUB_WORKSPACE:?must be set}"
: "${CCACHE_DIR:?must be set}"
: "${BUILD_DIR:?must be set}"

echo "=== HOST: $(hostname) -- $(nproc) cpus, $(free -h | awk '/Mem:/{print $2}') ram ==="

# rocm/pytorch lacks ninja/ccache/cmake; install per-run (ephemeral container).
dpkg-statoverride --list 2>&1 \
  | awk '$1=="messagebus" || $2=="messagebus" {print $NF}' \
  | xargs -r -n1 dpkg-statoverride --remove || true
apt-get update -qq
apt-get install -y --no-install-recommends cmake ninja-build ccache

export PATH=/opt/rocm/llvm/bin:$PATH
mkdir -p "$BUILD_DIR" "$CCACHE_DIR"
rm -f "$BUILD_DIR"/CMakeCache.txt
git config --global --add safe.directory "$GITHUB_WORKSPACE"

cmake -G Ninja -S "$GITHUB_WORKSPACE/llvm" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU" \
  -DLLVM_EXTERNAL_PROJECTS="device-libs;comgr" \
  -DLLVM_EXTERNAL_DEVICE_LIBS_SOURCE_DIR="$GITHUB_WORKSPACE/amd/device-libs" \
  -DLLVM_EXTERNAL_COMGR_SOURCE_DIR="$GITHUB_WORKSPACE/amd/comgr" \
  -DCOMGR_ENABLE_HOTSWAP_TRANSPILE=ON \
  -DHOTSWAP_TRANSPILER_LLVM_TOOLS_DIR="$BUILD_DIR/bin" \
  -DLLVM_USE_LINKER=lld \
  -DLLVM_CCACHE_BUILD=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_hip=ON

ninja -j "$(nproc)" -C "$BUILD_DIR" check-comgr

ccache -s
