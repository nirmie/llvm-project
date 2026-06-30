# HotSwap model-run CI bring-up log

Goal: get full HotSwap model E2E runs (pytorch + sglang) working on the
standalone GPU boxes and wrap them in a docker-based CI workflow on
`nirmie/llvm-project-hotswap` (branch `nisenthi/docker-ci`).

## Key decision: reuse the prebuilt `hotswap-transpile-repro` image

`scripts/setup.sh` in `harsh-amd/rocm-hotswap-testing` builds the **full
TheRock ROCm stack** (`THEROCK_ENABLE_ALL`, gfx942;gfx1250) with a
hotswap-enabled ROCR plus `librocr-hotswap.a` — a multi-hour build.

Instead, shark300 already has the image
`registry-sc-harbor.amd.com/rocm-hotswap/hotswap-transpile-repro:2026-06-25-interactive`
(107 GB) which already contains the entire built stack:

| Artifact | Path in image |
|---|---|
| hotswap COMGR | `/workspace/llvm-project/build/lib/libamd_comgr.so.3.3.0` |
| hotswap libhsa-runtime | `/workspace/rocm-systems/projects/rocr-runtime/build/rocr/lib/libhsa-runtime64.so.1.21.0` |
| intercept lib | `/workspace/rocm-hotswap-testing/build/libhotswap_intercept.so` |
| harness | `/workspace/rocm-hotswap-testing` |
| hipcc | `/usr/bin/hipcc` |
| rocm-systems hotswap tree | `/workspace/rocm-systems` |

So the model-run path = run the harness `make` targets (per
`docs/pytorch-runner.md` / `docs/sglang-runner.md`) inside this image,
pointing the env vars at the prebuilt libs above. No TheRock rebuild needed.

## Weights
- shark300 (gfx942): `/data/huggingface/hub/models--<org>--<name>` (HF cache)
- mi350 (gfx950): `/mnt/gfx_apps/models/<org>/<name>`

---

# Single-model scope: gemma-3-4b-it via SGLang (RUNBOOK-gemma)

Scope narrowed (user request) to one model: `google/gemma-3-4b-it` through the
SGLang HotSwap compare path, per `~/Downloads/RUNBOOK-gemma 1.md`.

## Runbook image
`registry-sc-harbor.amd.com/rocm-hotswap/alex_hotswap_wip:latest` (pullable).
The already-present `alex_wip:latest` on shark300 has the same layout:
- HotSwap COMGR: `/workspace/llvm-acc/build/lib/libamd_comgr.so.3.3.0`
- libhsa-runtime: `/workspace/rocm-systems/projects/rocr-runtime/build/rocr/lib/libhsa-runtime64.so`
- intercept lib: `/workspace/rocm-hotswap-testing/build/libhotswap_intercept.so`
- SGLang venv: `/workspace/venv/bin/python`
- harness: `/workspace/rocm-hotswap-testing`

Critical gotcha (runbook): `export LD_LIBRARY_PATH=/workspace/llvm-acc/build/lib`
so the runtime resolves `amd_comgr_3.2` — else the HotSwap pass fails.

## Weights acquisition (no gated HF download needed)
gemma-3-4b-it is gated on HF and shark300 has no HF token + can't reach the
gfx_apps NFS. But mi350 has the weights at
`/mnt/gfx_apps/models/google/gemma-3-4b-it` (8.1G). The two boxes can't SSH
each other directly (no DNS/keys), so streamed via the laptop in one pass:

```bash
ssh mi350 'tar -C /mnt/gfx_apps/models/google -cf - gemma-3-4b-it' \
  | ssh shark300 'mkdir -p ~/hotswap-data && tar -C ~/hotswap-data -xf -'
```

Lands at `~/hotswap-data/gemma-3-4b-it` on shark300 (mounted `-v ~/hotswap-data:/data`).

## Manual validation command (runbook Step 4, single `docker run`)
Run on shark300 (gfx942). `--group-add 44 109` = video/render GIDs (names absent
in image). Pick an idle GPU via `rocm-smi --showmemuse`.

## CI workflow
`docker-e2e-gemma.yml` — 2-leg matrix on the `gfx942` (shark300) and `gfx950`
(mi350) runners, GPU index 7 ("gpu8"), per-machine image, parses
`summary.json` (`equivalence.passed`) for the gate. PASS = run2 no proof
failures, no cache misses, equivalence verdict PASS.

## RESULT — shark300 (gfx942): PASS (2026-06-29)

Ran the runbook command verbatim (GPU index 7, image `alex_wip:latest`).
**No manual edits were needed** — the stock image + harness worked as-is, so
nothing to commit/push back to harbor.

```
proof_status:        translated   (10/10 kernels)
hotswap_cache:       10 hits / 0 misses (warm run2)
equivalence_passed:  true  (numerically_close, 0 token divergence)
local_tok_s ~10.96 | hotswap_tok_s ~8.20  (ratio 0.748)
```

Matches the runbook's documented "fully-passing path". Scratch/outputs under
`~/hotswap-ci-persist/sglang-gemma-scratch/sglang_gemma3_4b_it_e2e_<ts>/`.

## GPU index note
Boxes expose `card0..card7` (8 GPUs, indices 0-7). Per instruction "use gpu8",
interpreted as the 8th GPU = **index 7**. Used on both machines.

## Image distribution
- shark300: `alex_wip:latest` already local (rocm-hotswap namespace).
- mi350: pulled `alex_hotswap_wip:latest` (runbook image) — rocm-hotswap creds.
- Images to be deleted after validation to free disk; re-pull later.

## CI run results (commit ac79f60, run on self-hosted runners)

### gfx942 (shark300): GREEN
Full workflow green: model compare step + equivalence gate both pass.
`equivalence_passed: true` (`numerically_close`). Matches the manual run.

CI-wrapper bug found + fixed along the way: the gate step's
`find "$SCRATCH_HOST" -name summary.json` exits non-zero (permission-denied on
a root-owned, container-written subdir). Under GitHub's default
`bash -eo pipefail`, that failed the step even though summary.json was found
and the verdict was PASS. Fix: run the gate step with `shell: bash
--noprofile --norc {0}` (no `-e`) and `|| true` on the find. The equivalence
parsing also moved to `.github/workflows/scripts/gate-equivalence.py` (an
unindented python heredoc had been terminating the YAML block scalar).

### gfx950 (mi350): BLOCKED — SGLang baseline segfaults on MI350X
Not a CI or HotSwap problem: the **local (non-HotSwap) baseline** SGLang run
crashes during engine init:
```
triton .../compiler.py: kpack is deprecated starting from gfx950 ... kpack=2 -> 1
Fatal Python error: Segmentation fault
  File ".../sglang/srt/layers/utils/multi_platform.py", line 95 in forward_hip
  ... hip::hipLaunchKernel ...
RuntimeError: Rank 0 scheduler died during initialization (exit code: -11)  # SIGSEGV
```
The runbook is explicitly the *validated, fully-passing path on gfx942*.
gfx950 (MI350X) is "bring-up" per `docs/sglang-runner.md`; this image's
SGLang/Triton stack segfaults on gfx950 at HIP kernel launch, before HotSwap
is even exercised. Needs a gfx950-compatible SGLang/Triton stack (different
image / upstream fix) — out of scope for the CI wrapper.

No manual edits to the image were needed on either machine, so nothing was
committed/pushed to the harbor `hotswap` namespace.

---

# Per-GPU CI over issue #70 supported models

Per request, the e2e CI is split by GPU into two workflows, each iterating the
[martin-luecke/rocm-systems#70](https://github.com/martin-luecke/rocm-systems/issues/70)
"Model support plan" entries that (a) have a harness SGLang profile in the image
and (b) have weights available. The image profiles are: `qwen3_0_6b`,
`qwen3_5_4b`, `llama`, `gemma2_9b_it`, `gemma3_4b_it`, `gemma4_e2b_it`,
`phi4_mini`, `gpt_oss`, `custom` (note: the docs mention `mistral_7b` /
`deepseek_v2_lite` / `qwen3_30b_a3b`, but this image predates them).

Matrix (5 models — all Group-1 "works"-tagged with profile + weights):

| issue | model | profile |
|---|---|---|
| #72 | Qwen/Qwen3-0.6B | qwen3_0_6b |
| #73 | Qwen/Qwen3.5-4B | qwen3_5_4b |
| #74 | meta-llama/Llama-3.1-8B-Instruct | llama |
| #80 | google/gemma-2-9b-it | gemma2_9b_it |
| #81 | google/gemma-3-4b-it | gemma3_4b_it |

Workflows (`.github/workflows/`):
- `docker-e2e-gfx942.yml` — runs-on gfx942 (shark300). Weights under
  `~/hotswap-data/<name>` (staged: gemma-3-4b-it + llama local copy; qwen3_0_6b,
  qwen3_5_4b, gemma-2-9b-it streamed from mi350).
- `docker-e2e-gfx950.yml` — runs-on gfx950 (mi350). Weights read directly from
  `/mnt/gfx_apps/models/<org>/<name>` (gfx_apps NFS).
- Shared `scripts/run-sglang-model.sh` — one model: SKIP if weights absent, else
  `make sglang-hotswap-e2e-compare` in the image, then gate on `summary.json`.
- One matrix leg per model (= one status per model per GPU). Triggers:
  `workflow_dispatch` + nightly. Single runner per host ⇒ legs run serially
  (no GPU-7 contention).

Confirmed passing on gfx942: `llama` (Llama-3.1-8B) and `gemma3_4b_it`.

## gfx950 blocker root cause (sgl-kernel missing gfx950)

Diagnosed: torch and triton work on gfx950; the segfault is in **sgl-kernel** —
`sgl_kernel/common_ops*.so` embeds ONLY `gfx942` code objects (no gfx950, via
`roc-obj-ls`), so `hipLaunchKernel` finds no device binary on MI350X and
segfaults (first op: `gelu_tanh_and_mul`). Fix: rebuild/replace sgl-kernel with
gfx950 in its arch list (`GPU_ARCHS="gfx942;gfx950"`) or install a gfx950 wheel;
stopgap is forcing the native torch activation path. Until baked into the
gfx950 image, the gfx950 workflow legs fail at init (structure is correct and
will pass once the gfx950 sgl-kernel lands).


---

# gfx950 extended with issue #70 group representatives

The gfx950 workflow also runs the issue #70 group representatives on gfx_apps
that this image's SGLang text harness can run:

| issue | model | profile | gfx950 result |
|---|---|---|---|
| #71 (G1, dense) | Qwen/Qwen2.5-7B-Instruct | custom | PASS (numerically_close) |
| #83 (G2, MoE)  | Qwen/Qwen1.5-MoE-A2.7B-Chat | custom | runs+translates; verdict diverged (1/3 prompt) |

Neither has a dedicated profile, so they use SGLANG_PROFILE=custom + a generic
smoke prompts file (data/sglang/qwen3_5_4b/prompts/smoke.json). run-sglang-model.sh
now takes NAME PROFILE SUBPATH [PROMPTS] and keys scratch by NAME.

NOT runnable in this image (no VLM/diffusion harness targets): #95 Qwen2.5-VL,
#96 FLUX.1-schnell, #120 Wan2.2-TI2V-5B.

Both e2e workflows are on the hotswap default branch (pull_request +
workflow_dispatch + nightly).

---

# Independent PyTorch CI (PR#10 image): docker-e2e-pytorch-gfx950.yml

Separate workflow on gfx950 using the PR#10 image
(registry-sc-harbor.amd.com/hotswap/hotswap-pr10-gfx950) and the PyTorch hotswap
path. Gate = pipeline health (local + hotswap branches complete, 0 failed
translations); numerical equivalence surfaced but not gated. Stock-Alex SGLang
workflows kept as the small sample.

Working gfx_apps models (included): whisper_small (equiv PASS), flux_1_dev,
flux_1_schnell (translate end-to-end; equivalence drifts).

Tested but NOT yet included (fail in the hotswap translation branch on gfx950):
- sd3_5_large, wan2_2_ti2v_5b: transpiler gaps (v_div_scale_f32, s_set_pc_i64) -> HIP 209
- cogvideox_5b: runtime SIGABRT during compiled forward
- phi4_mini, parakeet_tdt_1_1b: intercept symbol-binding abort (no real hipModule*)
- mamba2_2_7b: transpiler refusal (cross-wave-lane-id-leak)
- falcon_mamba_7b: hotswap translated 77+ kernels but timed out (900s)
- stripedhyena_nous_7b: transformers offline+remote-code load bug (not gfx950)

Deps: the 3 working models need no extra deps (diffusers/accelerate already in
the image). mamba_ssm + causal-conv1d install via --no-build-isolation but mamba
still blocked at transpile. nemo (parakeet) downgrades transformers — do not bake.
