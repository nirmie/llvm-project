# HotSwap CI bring-up log

A detailed record of every alteration, hack, patch, irregularity, and bug hit
while standing up the HotSwap model-e2e CI on the Alola SLURM cluster. Intended
as the "why is it like this" reference for the next person.

## What the CI is

Three tiers, all on the self-hosted Alola runner; the runner only dispatches —
all heavy work runs on compute nodes via `srun` into the `hotswap-model-runner`
enroot image:

- **Tier 1 — `pytest-gate.yml`**: harness unit tests on a CPUONLY node (secs).
- **Tier 2 — `hotswap-pr.yml`**: comgr + device-libs + lld build + lit, CPUONLY node.
- **Tier 3 — `hotswap-e2e.yml`**: per-model GPU e2e (PyTorch via `run-model`,
  SGLang via `run-sglang-model`), two rendered tables + a README badge scoreboard.

Visibility: per-model detail on the GH Actions Summary (two tables); a committed
README scoreboard of dynamic shields.io badges fed by an orphan `ci-status`
branch (rocm-libraries convention).

## Bring-up steps (in order)

1. Authored the 3 workflows + in-container driver scripts
   (`scripts/pytorch-e2e.sh`, `scripts/sglang-e2e.sh`,
   `render-combined-summary.py`, `render-e2e-summary.py`, `emit-status-badges.py`).
2. Built the single `hotswap-model-runner` image (pytorch cp312/torch2.12 +
   sglang cp310/torch2.9.1 + shared HotSwap core) on the conductor; validated
   llama + gpt_oss + pytorch e2e on the conductor GPU.
3. Staged model weights to `/projects/hotswap-ci/models` (compute-visible NFS),
   HF-direct to Alola (faster than cross-site rsync).
4. **M1** — pushed image to Harbor; **enroot import** to an Alola `.sqsh`.
5. **M2** — pointed `hotswap-e2e.yml` at the single image; event-driven matrix
   (rep on PR, full nightly, dispatch both).
6. **M3/M4/M5** — badge publish to orphan `ci-status` branch + README scoreboard
   + nightly schedule + per-tier workflow badges.
7. Moved the GH Actions runner to run **host-direct on login-04** (no container)
   with a respawn loop + `@reboot` cron.
8. Wired **comgr-under-test** injection so the e2e runs the transpiler from the
   branch under test, not the image's baked comgr.

## Info dump — irregularities, bugs, errors, and fixes

### Image / enroot / SLURM placement
- **Detached `enroot import` on the login node died mid-"Extracting image
  layers"** with no DONE line and no output file — the login-node session/cgroup
  cleanup killed it. *Fix:* run the import as an **`sbatch` job on a CPUONLY
  compute node** with `ENROOT_SQUASH_OPTIONS="-comp zstd -b 1048576"` (per the
  MLSE runbook). Never `setsid`/`nohup` it on the login node.
- **`pyxis: [ERROR] No such file or directory: /home/AMD/nisenthi/...sqsh`** on a
  GPU node (`smci355-ccs-aus-*`) even though the file existed. Root cause:
  **Alola spans two sites (MARKHAM/AUSTIN node feature); Austin GPU nodes don't
  mount the Markham NFS** (`/home`, `/cluster`, `/projects`), and pyxis reads the
  image before triggering automounts. *Fix (two parts):* (a) put the image on
  **`/cluster`** (cluster-wide on Markham), and (b) constrain GPU jobs with
  **`--constraint="GFX950&MARKHAM"`** (quote the `&` so bash doesn't background
  it). The tell-tale was the paired `couldn't chdir to <home path>: ... going to
  /tmp instead`.
- **`docker run ... --group-add render` failed** ("Unable to find group render")
  on the conductor — the group is unnamed. *Fix:* numeric GIDs (`--group-add 44`
  video, `--group-add 993` render; `/dev/kfd` is group 993).

### Runner
- **Recurring `BrokerServer SocketException (125): Operation canceled`** — runner
  showed `online` but stopped dispatching; jobs stuck queued behind an idle
  runner. Two compounding causes: (a) a network idle-timeout dropping the runner's
  long-poll to GitHub, and (b) **TWO runner processes** (one per dev container)
  sharing the **same `.runner` registration**, evicting each other. *Fix:* exactly
  **one** runner, run **host-direct on login-04** (the bare host has
  `srun/squeue/scancel/git/gh/python3` + munge — no container needed), wrapped in
  a `while true; do ./run.sh; sleep 10; done` respawn loop, started via `@reboot`
  cron (host-local; NOT systemd-user, whose enable-symlink lives on NFS-shared
  `~/.config` and would spawn a duplicate on login-03).
- **Fresh `enroot start` dev containers had no `~/ci/actions-runner`** — the
  runner lives on the NFS home, which must be bind-mounted into the container
  (`-m /home/AMD/$USER:... -m /cluster:... -m /etc/slurm:... -m /run/munge:...`).
  Mooted by switching to host-direct.

### Orphaned allocations
- **`cancel-in-progress` orphaned the `srun`** on the compute node — the runner
  killed the step shell but the SLURM job ran until `--time` expired (confirmed:
  a `cancelled` GH run held a CPU node 37+ min). *Fix:* an `always()` cleanup step
  in every tier that `scancel`s the run's uniquely-named job (`hotswap-e2e-<run_id>-<model>` /
  `hotswap-pr-<run_id>` / prefix match) on success, failure, or cancellation.

### Checkout / NFS performance
- **`actions/checkout` crawled at ~7 files / 2 min** — it materialized the entire
  100k-file LLVM tree onto NFS home for jobs that only need
  `.github/workflows/scripts/*`. *Fix:* `sparse-checkout: .github` + `fetch-depth:
  1`. (First run after the switch is slow once — it deletes the old full tree from
  NFS — then steady-state is seconds.) The lit tier keeps a full checkout (it
  builds comgr).

### SGLang
- **`llama produced no summary.json`** though it ran. The baked
  `/opt/sglang-repro/run_sglang_e2e.sh` **hardcodes** `SGLANG_SCRATCH_ROOT=$REPRO_ROOT/scratch`
  (`/opt/sglang-repro/scratch`, inside the ephemeral container), overwriting the
  `/output/<p>` we export — so the gate + host renderer never saw it. *Fix:*
  `sglang-e2e.sh` copies `/opt/sglang-repro/scratch/.` → `/output/<p>` after
  `run-sglang-model`. (Proper fix later: make the baked script honor the env;
  needs an image rebuild.)

### comgr-under-test (the big one)
- **qwen2.5-7b: `RuntimeError: HIPBLAS_STATUS_INTERNAL_ERROR ... hipblasSgemm`.**
  - First mistake: I reported it "resolved" by reading the model JSON's static
    **`blocked_on` field** echoed at startup — NOT a live result. Lesson: that
    "is resolved; now reaches equivalence" line is a config note.
  - Real cause #1: the e2e was injecting the branch comgr (`--comgr-runtime` →
    LD_PRELOAD, chain verified through `pytorch-e2e.sh` → `run_hotswap_compare_debug.sh`
    → Makefile) **but pairing it with the image's OLD baked LLVM tools**
    (`llvm-hotswap-artifacts/bin`). Mixed comgr+tools → bad GEMM kernel. *Fix:*
    mount the **whole branch build dir** and use comgr (`lib/`) **and** tools
    (`bin/`) from the **same build** — mirroring the archived `pytorch-e2e.yml`
    (`$BD:$BD`, `COMGR_TOOLS_DIR=$BD/bin`). Staged at `/cluster/hotswap-ci/comgr-override/{lib,bin}`.
  - Real cause #2 (surfaced after #1): `torch.AcceleratorError: CUDA error: no
    kernel image is available for execution on the device`. The rocBLAS Tensile
    **`HS_HPA ... fallback_gfx1250.hsaco` was renamed aside** (`.disabled-for-phi4-test`,
    originally `.disabled-by-freeze`) as a workaround for an *old* comgr that
    refused that kernel. The current branch comgr handles it. *Fix:* re-enable
    (rename back to `.hsaco`) — both in the conductor ground-truth tree and at CI
    runtime in `pytorch-e2e.sh`. Verified in-image on the conductor GPU: with
    matching comgr+tools **and** the fallback re-enabled, the "no kernel image"
    error is gone and qwen reaches the expected numerical-divergence state.

### Earlier (pre-this-phase) build/runtime fixes (for completeness)
- SGLang build clobbered ROCm torch with CUDA torch 2.9.1 → cp310 venv +
  `tested-requirements --no-deps` (ROCm torch 2.9.1 from repo.radeon.com).
- Build deps: deadsnakes python3.10, python3-dev/zlib1g-dev/libxml2-dev (triton
  cmake), `ROCM_HOME`/hipconfig (aiter), cargo/rustc (sglang), xxd/lld.
- torch import: `libroctx64/librccl/librocm_sysdeps` → `LD_LIBRARY_PATH` at the
  TheRock dist + a `librccl.so.1` symlink.
- HotSwap intercept SIGABRT "cannot find rocr_hotswap_patch_elf" → point
  `SGLANG_BASE_LIBHSA` at the **dist** (patched) libhsa, not the rocr-runtime build copy.
- gpt_oss MXFP4 swizzle crash → `GPT_OSS_SGLANG_DECOMPOSE_MXFP4=1`.
- gpt_oss teacher-forced OOM → made teacher-forced non-fatal/skippable
  (`SGLANG_SKIP_TEACHER_FORCED=1`); it's diagnostic, not the gate.
- CI "failure" though healthy → gate from `summary.json`, not `run-model` exit
  code (the harness exits non-zero on expected `diverged`).
- `git push` 403 (host `~/.git-credentials` holds the AMD `nisenthi_amdeng`
  token) → push with an inline credential helper feeding `gh auth token` (active
  account `nirmie`): `git -c credential.helper= -c credential.helper='!f(){ echo username=nirmie; echo password=$(gh auth token); };f' push`.

## Standing hacks / temporary workarounds (revisit)

- **comgr override is a pre-staged `.so`+tools on `/cluster`** (built from PR #101
  branch). Proper end state (**M7**): the lit tier builds comgr from the branch
  under test (default `hotswap`) and publishes it; e2e `needs:` lit and injects it.
- **Tensile re-enable + sglang scratch-copy are runtime renames/copies** in the
  driver scripts; proper fix is an image rebuild that doesn't disable the Tensile
  lib and makes the sglang reproducer honor `SGLANG_SCRATCH_ROOT`.
- **Models serialize on one runner** (matrix jobs run one at a time). **M8**:
  submit all to SLURM at once and let it schedule.
- **Runner is a personal host-direct process on login-04**; **M6**: move to the
  service account / dedicated CI host (ARC is NOT an option — its K8s runners have
  no Alola SLURM client).
- **git push** still needs the inline-credential-helper hack until
  `~/.git-credentials` is refreshed.

## Confluence pages used (MLSE space unless noted)

- **Preparing your enroot image** (1170171553) — `enroot import` on a CPUONLY
  node + `ENROOT_SQUASH_OPTIONS` zstd. (PDF copy at `~/MLSE-Preparing your enroot
  image-*.pdf` on the conductor.)
- **srun inside enroot container** (1331716047) — slurm-smd-client + the
  `/etc/slurm` + `/run/munge` + passwd/group bind-mounts to `srun` from a container.
- **Using Alola Login Nodes 3 and 4 for Development and GPU Job Submission**
  (1399483941) — login-03/04 for dev; the MARKHAM vs AUSTIN node distinction and
  "Austin nodes do not share /home (mounted at /home_aus)"; `--constraint "MARKHAM"`.
- **Alola Fair Use Policy** (1443726597) — login 3/4 for interactive/short work,
  limited container usage (motivated the lean host-direct runner).
- **Alola container support** (1166676873) / **Alola cluster user resources**
  (897801231) — enroot/pyxis basics, persistent-work guidance.
- **ARC Runner Architecture Reference** (1682895806, SHARK) / **Request for
  GitHub Actions Runners** (553717565, SI) — AMD's managed-runner path; noted ARC
  doesn't fit SLURM-dispatch CI.
- **GPT-OSS e2e runbook** + **AMD-Triton/triton-mi450** (migrated triton_kernels)
  — the sglang reproducer setup (cp310/ROCm-torch `--no-deps`).
