# HotSwap model status

Live scoreboard of the HotSwap transpiler (gfx1250 -> gfx950/gfx942) end-to-end
results, one row per model, one column per framework. Badges are dynamic: the
[`Hotswap E2E (combined)`](workflows/hotswap-e2e.yml) workflow's `aggregate` job
writes a shields-endpoint JSON per `(framework, model)` to the orphan
[`ci-status`](https://github.com/nirmie/llvm-project/tree/ci-status) branch on
every nightly + dispatch run, so these update without committing to source
history. Per-model failure detail lives in each run's **Summary** page (two
tables: transpile proof, equivalence verdict + divergence counts, cache hits).

Legend: ![pass](https://img.shields.io/badge/pass-brightgreen) transpiled +
equivalent &nbsp; ![diverged](https://img.shields.io/badge/diverged-yellow)
transpiled, accumulation-order token flips (expected) &nbsp;
![fail](https://img.shields.io/badge/fail-red) transpile/baseline did not
complete &nbsp; ![pending](https://img.shields.io/badge/pending-lightgrey)
weights/image not staged yet.

| Model | Group | PyTorch e2e | SGLang e2e |
|-------|-------|-------------|------------|
| qwen2.5-7b-instruct | G1 dense LLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen2_5_7b_instruct.json) | n/a |
| phi4-mini | G1 dense LLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/phi4_mini.json) | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/sglang/phi4_mini.json) |
| llama-3.1-8b-instruct | G1 dense LLM | n/a | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/sglang/llama.json) |
| qwen1.5-MoE-A2.7B | G2 MoE | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen1_5_moe_a2_7b_chat.json) | n/a |
| qwen2.5-vl-7b-instruct | G3 VLM | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/qwen2_5_vl_7b_instruct.json) | n/a |
| stable-diffusion-3.5-large | G4 diffusion | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/sd_3_5_large.json) | n/a |
| bge-large-en-v1.5 | G5 encoder | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/nirmie/llvm-project/ci-status/pytorch/bge_large_en_v1_5.json) | n/a |

> `diverged` is a **pass** for the transpile gate: gfx1250->gfx950 changes
> floating-point accumulation order, which flips a few low-confidence tokens.
> The forward-KL equivalence gate treats it as expected and reports it; it is
> not a CI failure. A red `fail` means the baseline or the transpile pipeline
> did not run end-to-end.
