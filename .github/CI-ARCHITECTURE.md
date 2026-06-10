# Hotswap CI architecture

What the hotswap CI tests, where it runs, and how the pieces fit. Two
workflows live in this repo's `.github/workflows/`:

| Workflow | Triggers | What it proves |
|---|---|---|
| `hotswap-pr.yml` (**lit**) | every PR + push to `hotswap` | the comgr **transpiler builds** and its **lit tests** pass (gfx1250→gfx950/942 kernel raising at the IR level) |
| `pytorch-e2e.yml` (**model e2e**) | every PR + dispatch | full **models run end-to-end** through the transpiler and stay numerically equivalent |
| `hotswap-e2e.yml` (**combined, WIP**) | dispatch | same as e2e but **PyTorch + SGLang** in one run, two tables, continuous per-job summary |

## What "hotswap" is testing

The product under test is the **comgr HotSwap transpiler** (in
`llvm-project`): it rewrites GPU kernels compiled for **gfx1250** (MI450)
into **gfx950** (MI350) / **gfx942** (MI300) at load time, so code built for
unreleased silicon runs on available silicon.

The e2e exercises it on real models:

```
            model (HF weights)
                 │
                 ▼
   ┌─────────────────────────────┐     gfx_override_target=gfx1250
   │  run the model on the GPU    │  ← GPU *reports* as gfx1250, so triton
   │  (sglang or pytorch harness) │    JIT + rocBLAS/Tensile emit gfx1250
   └─────────────────────────────┘    kernels
                 │ kernel load (HSA)
                 ▼
   ┌─────────────────────────────┐
   │ libhotswap_intercept.so      │  ← intercepts the gfx1250 code object
   │  + patched libhsa-runtime64  │
   └─────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │ libamd_comgr.so (transpiler) │  ← gfx1250 → gfx950 (llc/llvm-mc/lld)
   │  HSA_HOTSWAP_CACHE_DIR cache  │    proof row per kernel; cached
   └─────────────────────────────┘
                 │ gfx950 code object
                 ▼
            runs on the gfx950 GPU
                 │
                 ▼
   compare: "local" branch (native gfx950) vs "hotswap" branch
   → teacher-forced equivalence (forward KL gate); verdict in summary.json
```

`diverged` verdicts are **expected and not failed**: accumulation-order
differences flip a token; the gate is whether the transpile pipeline ran the
model end-to-end (+ for sglang, the equivalence checker's `passed`).

## Where it runs (physical layout)

```
GitHub (nirmie/llvm-project)
   │  workflow_dispatch / pull_request
   ▼
Self-hosted runner  ── on the ALOLA LOGIN NODE (enroot dev container)
   │  does NO GPU work itself; it only orchestrates
   │  $GITHUB_STEP_SUMMARY is rendered here
   ▼  srun --container-image=<sqsh> --container-mounts=...
SLURM compute node (defq)
   ├─ lit:  CPU node (--constraint=CPUONLY)  → build comgr + ninja check-comgr
   └─ e2e:  GPU node (--constraint=GFX950)   → run-model / run-sglang-model
        inside a fresh enroot from the sqsh image
```

One runner = one job at a time (known limitation; jobs serialize. Fix later:
multiple runner instances so srun's parallelize — they're lightweight
orchestrators, real work is on compute nodes).

## Storage (all NFS, compute-visible)

| Path | Holds | Filer |
|---|---|---|
| `/projects/hotswap-ci/models/<org>/<model>` | model weights (HF-downloaded / staged) | ags-pure-mkm-01 (98T free) |
| `/cluster/hotswap-ci/model-configs/` | CI model configs (`/projects` paths), overlaid at runtime | ags-pure-mkm-01 |
| `/cluster/hotswap-ci/rocm-hotswap-testing/` | pinned harness checkout (scripts/data/runtime) bind-mounted into the container | ags-pure-mkm-01 |
| `/cluster/images/nisenthi/*.sqsh` / `/home/AMD/nisenthi/*.sqsh` | enroot container images | |
| `/home/AMD/nisenthi/hotswap-cache-shared/` | persistent transpile cache (`/cache`) | local /home |
| `/home/AMD/nisenthi/ci/.../pytorch-output/` | per-run output (`/output`): summary.json/md, run.log, proof | local /home |

Note: model weights live on the Markham gfx_apps fleet (login-only) and the
Rockdale fleet (conductor-only); CI uses copies selectively staged to
`/projects` (compute-visible, service-account readable). HF-direct-to-Alola
(~63 MB/s) is the fastest staging path (`hf-stage-small-models.sh`).

## Containers

```
rocm/pytorch (upstream)
   └─ pytorch-runner  ── + comgr/libhsa/intercept/gfx_override (C++ hotswap
        │                 artifacts), cp312 venv (torch 2.12+rocm7.2),
        │                 rocm-hotswap-testing repo, gfx1250 Tensile libs,
        │                 `run-model <stem>`  (pytorch e2e)
        └─ sglang-runner ── + cp310 venv (torch 2.9.1+rocm7.2 from
                            repo.radeon.com, per tested-requirements.txt) with
                            sglang+triton+triton_kernels+aiter editable,
                            `run-sglang-model <profile>`  (sglang e2e)
```

`sglang-runner` is a **superset of pytorch-runner** → a single image can run
**both** frameworks (it has both venvs + both run wrappers). The combined CI
should use `sglang-runner` as the one `CONTAINER_IMAGE`.

Config/harness delivery is **runtime overlay**, not baked: the workflow
bind-mounts the harness checkout at `/harness` and the corrected configs at
`/ci-configs`; the in-container run-script copies them over the image's frozen
copies (container is `--container-writable`, ephemeral). So harness/config
changes are a git pull — no image rebuild. Only `deps/venvs` changes need a
rebuild.

## Model suite (one representative per group — martin-luecke/rocm-systems#70)

| Group | Workload | PyTorch rep | SGLang profile | Weights |
|---|---|---|---|---|
| 1 Dense LLM | hf_causal_lm | `qwen2_5_7b_instruct`, `phi4_mini` | `llama`, `phi4_mini` | staged |
| 2 MoE | hf_causal_lm | `qwen1_5_moe_a2_7b_chat` | — | pending |
| 3 VLM | hf_vision_lm | `qwen2_5_vl_7b_instruct` | — | pending |
| 4 Diffusion | hf_diffusion | `sd_3_5_large` | — | staged |
| 5 Encoder | hf_encoder (new) | `bge_large_en_v1_5` (boilerplate) | — | pending |

## Summary flow (combined `hotswap-e2e.yml`)

```
matrix: one job per (framework, model)
   each job → its own srun → its own GPU allocation
   each job writes its step summary when it finishes
        → run Summary page grows CONTINUOUSLY (per SLURM job)
aggregate job (needs: all, if: always)
   → render-combined-summary.py → TWO tables (PyTorch | SGLang)
```

Pending models (no weights / workload / image) render as `⏳ pending`, not
failures, so every group is visible.

## Current status (2026-06-10)

- **lit CI**: stable on Alola (~247/263).
- **PyTorch e2e**: working on gfx950 (phi4 `translated 54/54`, `diverged` = expected). PR suite live.
- **SGLang**: image build in progress on the corrected (cp310 + tested-requirements ROCm torch) path; combined workflow ready, SGLang rows pending until the image validates. Open follow-up: unify on the single `sglang-runner` image; multiple runners for parallel srun.
