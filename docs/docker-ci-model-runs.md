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

