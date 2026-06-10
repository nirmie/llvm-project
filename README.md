# AMD Fork of The LLVM Compiler Infrastructure
#

## HotSwap model CI status

Live end-to-end status of the HotSwap transpiler (gfx1250 -> gfx950/gfx942),
one row per model, one column per framework. Badges are dynamic: the
[`Hotswap E2E (combined)`](.github/workflows/hotswap-e2e.yml) workflow publishes
a status JSON per `(framework, model)` to the orphan
[`ci-status`](https://github.com/nirmie/llvm-project/tree/ci-status) branch on
every nightly + dispatch run, so they update without committing to source
history. Per-model failure detail (transpile proof, equivalence verdict +
divergence counts, cache hits) lives on each run's **Summary** page.

| Model | Group | PyTorch e2e | SGLang e2e |
|-------|-------|-------------|------------|
| qwen2.5-7b-instruct | G1 dense LLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen2_5_7b_instruct.json) | n/a |
| phi4-mini | G1 dense LLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/phi4_mini.json) | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/sglang/phi4_mini.json) |
| llama-3.1-8b-instruct | G1 dense LLM | n/a | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/sglang/llama.json) |
| qwen1.5-MoE-A2.7B | G2 MoE | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen1_5_moe_a2_7b_chat.json) | n/a |
| qwen2.5-vl-7b-instruct | G3 VLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen2_5_vl_7b_instruct.json) | n/a |
| stable-diffusion-3.5-large | G4 diffusion | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/sd_3_5_large.json) | n/a |
| bge-large-en-v1.5 | G5 encoder | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/bge_large_en_v1_5.json) | n/a |

Legend: **pass** = transpiled + equivalent &middot; **diverged** = transpiled,
accumulation-order token flips (expected, not a failure) &middot; **fail** =
baseline/transpile did not complete &middot; **pending** = weights/image not
staged yet. `diverged` is a pass for the transpile gate: gfx1250->gfx950 changes
floating-point accumulation order, flipping a few low-confidence tokens; the
forward-KL equivalence gate treats it as expected.

---

The AMD fork aims to contain all of [upstream LLVM](https://github.com/llvm/llvm-project), and also includes several AMD-specific additions in the `llvm-project/amd` directory:

- **amd/comgr** - The Code Object Manager API, designed to simplify linking, compiling, and inspecting code objects (code owner: [@lamb-j](https://www.github.com/lamb-j))
- **amd/device-libs** -The sources and CMake build system for a set of AMD-specific device-side language runtime libraries (code owner: [@b-sumner](https://www.github.com/b-sumner))
- **amd/hipcc** - A compiler driver utility that wraps clang and passes the appropriate include and library options for the target compiler and HIP infrastructure (code owner: [@david-salinas](https://www.github.com/david-salinas))

See the README files in respective subdirectories for more information on these AMD-specific projects. While the AMD fork aims to otherwise follow upstream as closely as possible, there are several outstanding differences.

- *OpenMP* - The AMD fork contains several changes:
    * Additional optimizations for OpenMP offload
    * Host-exec services for printing on-device and doing malloc/free from device
    * Improved support for OMPT, the OpenMP tools interface
    * Driver improvements for multi-image and Target ID features
    * OMPD support, implements OpenMP D interfaces.
    * ASAN support for OpenMP.
    * MI300A Unified Shared Memory support

- *Heterogeneous Debugging* - A prototype of debug-info supporting AMDGPU targets, affecting most parts of the compiler, is implemented as documented in `docs/AMDGPULLVMExtensionsForHeterogeneousDebugging.rst` but is an ongoing work-in-progress. Fundamental changes are expected as parts of the design are adapted for upstreaming.
- *Address Sanitizer* - Changes were added to `santizer_common` and `asan` libraries in `compiler-rt` to support AMD GPU address sanitizer error detection and reports.  These changes are intended to be upstreamed.  The instrumentation pass changes have already been upstreamed.
- *Reverted Patches* - For upstream patches that break internal testing, we may temporarily revert these patches until the testing issues are resolved. We maintain a list of reverted upstream patches in `llvm-project/revert_patches.txt`.
