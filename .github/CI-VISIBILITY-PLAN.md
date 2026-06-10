# Hotswap CI + model-status visibility plan

Goal: a clear, low-maintenance view of **which models pass/fail** for both
PyTorch and SGLang, plus per-model failure detail — modeled on
[ROCm/rocm-libraries](https://github.com/ROCm/rocm-libraries) (a committed
README table of dynamic status badges, updated live by CI with no per-run
commits to the source history).

## Two-layer visibility

### Layer 1 — README status table (the "scoreboard", rocm-libraries-style)
A committed table in the README, **one row per model**, **two columns
(PyTorch / SGLang)**, each cell a **dynamic badge** (committed once, auto-updates):

```
| Model                | Group       | PyTorch e2e        | SGLang e2e         |
|----------------------|-------------|--------------------|--------------------|
| qwen2.5-7b-instruct  | G1 dense    | ![](endpoint .../pytorch/qwen2_5_7b_instruct.json) | ![](endpoint .../sglang/llama.json) |
| phi4-mini            | G1 dense    | ![](.../pytorch/phi4_mini.json)                    | ![](.../sglang/phi4_mini.json)      |
| sd-3.5-large         | G4 diffusion| ![](.../pytorch/sd_3_5_large.json)                 | n/a                |
| qwen1.5-MoE          | G2 MoE      | ![](.../pytorch/qwen1_5_moe.json)                  | ![](.../sglang/gpt_oss.json)        |
| ...                  | ...         | ...                | ...                |
```

How the badges stay current **without churning `main`**:
- The combined e2e workflow's `aggregate` job writes one shields.io-endpoint
  JSON per `(framework, model)` — `{schemaVersion:1,label,message,color}` with
  `pass` (green) / `diverged` (yellow, expected) / `fail` (red) / `pending`
  (grey) — to an **orphan `ci-status` branch** (isolated from source; never
  shows up in normal dev/diffs).
- README badges are `https://img.shields.io/endpoint?url=raw.githubusercontent.com/<repo>/ci-status/<fw>/<model>.json`.
- Result: README markdown committed once; per-model status updates live from CI;
  only the orphan branch receives status commits.

(Alternatives if even the orphan branch is unwanted: per-model GitHub Actions
`badge.svg` needs one workflow per model — too many; or just link the latest
nightly run, whose matrix job list is itself a green/red board. The orphan-branch
+ endpoint-badge approach is the rocm-libraries convention and scales to N models.)

### Layer 2 — per-model failure detail (keep what we have, GH Actions Summary)
Unchanged: the combined workflow renders **two tables** (PyTorch / SGLang) to
`$GITHUB_STEP_SUMMARY` via `render-combined-summary.py`, each row showing the
metric (transpile proof, equivalence status + divergence counts, cache hits) and
result. Each model keeps `summary.json` / `summary.md` as run artifacts for
drill-down ("what is model X failing on"). A README badge click links to the
model's latest run section.

## CI structure (3 tiers, on every PR)

```
Tier 1  pytest-gate.yml   harness unit tests (config/env/equivalence-math/shims)
        CPU node, secs, GPU tests auto-skip                     [DONE]
Tier 2  hotswap-pr.yml    comgr transpiler build + lit          [DONE, live]
Tier 3  hotswap-e2e.yml   per-model GPU e2e matrix, two tables  [DONE, dispatch-only]
```

- **Single image**: all tiers use `hotswap-model-runner` (superset of
  pytorch-runner: both venvs + `run-model` + `run-sglang-model`). Validated:
  llama PASS, gpt_oss diverged-but-transpiled, no runtime hacks.
- **Gate**: transpile ran end-to-end. `diverged` (gfx1250→gfx950 accumulation)
  is reported, not failed — for both pytorch and sglang. Teacher-forced is
  skipped (`SGLANG_SKIP_TEACHER_FORCED=1`), it's diagnostic, not the gate.

## Setup steps (to make it live)

1. **Image to Alola.** `docker push` `hotswap-model-runner` → Harbor; `enroot
   import` → Alola sqsh at `/home/AMD/nisenthi/...hotswap-model-runner...sqsh`.
2. **Point `hotswap-e2e.yml` at the single image** (replace PYTORCH_IMAGE/
   SGLANG_IMAGE with the one `hotswap-model-runner` sqsh) and flip
   `sglang_ready=true`.
3. **Status publish.** Add to the `aggregate` job: for each model, emit the
   shields endpoint JSON and `git push` it to the orphan `ci-status` branch
   (a ~10-line step; uses a deploy token, only touches `ci-status`).
4. **README table.** Add the model×{pytorch,sglang} table with endpoint badges
   (committed once).
5. **Nightly full sweep.** `schedule:` trigger running the full model matrix
   (not just the PR rep-suite) so the scoreboard reflects every model nightly;
   PRs still run the short rep-suite for speed.
6. **Coarse badge.** Top-of-README workflow badges for the three tiers
   (`actions/workflows/<wf>.yml/badge.svg`).

## Single-runner caveat (known, deferred)
One self-hosted Alola runner serializes jobs; matrix jobs + lit still publish
their summaries as they finish (continuous), but srun's don't parallelize.
Fix later: multiple runner instances on the login node.

## Status of work (2026-06-10)
- Tiers 1–3 workflows authored; combined two-table renderer validated against
  real llama (PASS) + gpt_oss (diverged) summaries.
- `hotswap-model-runner` image built + e2e-validated on the conductor (no hacks).
- Remaining: steps 1–6 above (image→Alola, single-image wiring, status-publish +
  README badges, nightly sweep).
