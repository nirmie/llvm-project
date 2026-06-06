#!/usr/bin/env bash
# CI build + lit script for the hotswap branch.
#
# Designed to run inside a fresh rocm/pytorch enroot container,
# dispatched from .github/workflows/hotswap-pr.yml as:
#   srun --container-image=<sqsh> --container-mount-home \
#        bash .github/workflows/scripts/hotswap-build.sh
#
# Required env vars:
#   GITHUB_WORKSPACE  - source tree root (checked out by actions/checkout)
#   CCACHE_DIR        - persistent ccache dir on NFS so it survives SLURM jobs
#
# Locally testable on any Linux host that has the rocm/pytorch image
# available locally (e.g. on Alola inside the dev container):
#   GITHUB_WORKSPACE=$(pwd) CCACHE_DIR=/tmp/ccache \
#     bash .github/workflows/scripts/hotswap-build.sh

set -euxo pipefail

: "${GITHUB_WORKSPACE:?must be set (workspace root)}"
: "${CCACHE_DIR:?must be set (persistent ccache dir)}"

echo "=== HOST: $(hostname) -- $(nproc) cpus, $(free -h | awk '/Mem:/ {print $2}') ram ==="

# Fresh container from base sqsh: ninja, ccache, and cmake aren't
# in rocm/pytorch -- the login-node dev container has them only
# because envsetup's add_devtools_enroot_image.sh baked them into
# the *_dev.sqsh overlay. We pull the BASE sqsh, so install on
# every run (~30s). Also clear the stale dpkg messagebus
# statoverride that blocks apt on this image (known enroot quirk
# -- the rootfs references a system group that doesn't exist in
# the running container's /etc/group).
dpkg-statoverride --list 2>&1 \
  | awk '$1=="messagebus" || $2=="messagebus" {print $NF}' \
  | xargs -r -n1 dpkg-statoverride --remove
apt-get update -qq
apt-get install -y --no-install-recommends cmake ninja-build ccache

# LLVM toolchain lives at /opt/rocm/llvm/bin in the rocm/pytorch
# image (clang, ld.lld, llvm-mc, FileCheck, not, llvm-dis,
# llvm-readelf, llvm-objdump). Put it first on PATH so
# LLVM_USE_LINKER=lld finds ld.lld before host gcc would look for
# the system linker.
export PATH=/opt/rocm/llvm/bin:$PATH

# Build on compute node's local /tmp -- fast local disk on a
# dedicated CPU node (vs. shared NFS or contended login node).
# Ephemeral: wiped when the SLURM allocation ends. ccache (on NFS,
# above) carries cross-job acceleration so cold compiles only happen
# the very first time a translation unit is seen.
BUILD_DIR=/tmp/build
mkdir -p "$BUILD_DIR"

# Always wipe a stale CMakeCache.txt: this workflow has gone through
# several incompatible layouts and a stale cache makes cmake fail
# with confusing errors. ccache (separate dir) still amortizes
# individual cc1 invocations, so a fresh configure stays fast.
rm -f "$BUILD_DIR"/CMakeCache.txt

# Workspace is NFS-mounted, owned by a non-root uid. Container runs
# as root. comgr reads git commit/branch into COMGR_GIT_COMMIT /
# COMGR_GIT_BRANCH at configure time; without safe.directory those
# end up "not-available".
git config --global --add safe.directory "$GITHUB_WORKSPACE"

# Build invocation:
#   * comgr + device-libs live inside the LLVM build tree as
#     LLVM_EXTERNAL_PROJECTS so libamd_comgr.so ends up in
#     $BUILD_DIR/lib next to LLVM libs and lit-built test binaries
#     pick OUR libamd_comgr.so by normal build-tree lookup (not
#     /opt/rocm/lib).
#   * device-libs is listed FIRST so its targets register the
#     AMD_DEVICE_LIBS global property before comgr's
#     DeviceLibs.cmake (line 151) reads it.
#   * HOTSWAP_TRANSPILER_LLVM_TOOLS_DIR is baked into the comgr
#     build; raise_cli shells out to llc / llvm-mc / ld.lld using
#     this dir.
#   * CMAKE_DISABLE_FIND_PACKAGE_hip: comgr/test/CMakeLists.txt:214
#     calls find_package(hip), which transitively loads
#     /opt/rocm/lib/cmake/AMDDeviceLibsConfig.cmake and collides
#     with our in-tree device-libs targets. The result is unused,
#     so disabling is safe.
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

# -j 64 matches the compile-09 node size. compile-11 has 128 cores
# but the marginal gain from -j 128 on a 4-minute build isn't worth
# the risk of OOM on a node with a noisy neighbor.
ninja -j 64 -C "$BUILD_DIR" check-comgr

ccache -s
