# Hotswap CI runner setup

How to provision a self-hosted GitHub Actions runner that can serve
`.github/workflows/hotswap-pr.yml`. This bootstrap doc is written for running
on a single workstation in a contained, no-sudo, one-job-at-a-time mode.
OSCCI fleet reproduction notes are at the bottom.

## Layout (everything outside `$HOME`)

All files this workflow needs live under the repo's parent directory
(`/home/nisenthi/hotswap/test/`):

```
/home/nisenthi/hotswap/test/
├── llvm-project/              # this repo
├── actions-runner/            # extracted GitHub Actions runner
└── hotswap-ci-persist/
    ├── build/                 # ninja build dir (incremental across runs)
    └── ccache/                # ccache cache
```

Nothing is written to `$HOME` and no system paths (`/var/lib`, `/etc/...`)
are touched.

## Host prerequisites

- Linux (Ubuntu 22.04 or 24.04 tested).
- AMD GPU with ROCm KFD driver loaded: `/dev/kfd` and `/dev/dri/renderD*`
  exist (not used by the PR lit job, listed for future GPU-using workflows).
- **GPU index constraint on this host:** gpu0 and gpu1 are dead, gpu2 is in
  use by other workloads. GPU-using workflows must target gpu index 3 or
  higher (`HIP_VISIBLE_DEVICES=3` or higher). The current PR lit workflow
  does not run on the GPU at all.
- Docker installed, runner user in `docker` group (already done on this
  machine).
- At least 100 GB free for image cache + persistent build + ccache.

## Persistent directories

Already created on this machine. To recreate elsewhere:

```bash
mkdir -p /home/nisenthi/hotswap/test/hotswap-ci-persist/{build,ccache}
```

`hotswap-pr.yml` bind-mounts these into the job container as `/persist/build`
and `/persist/ccache`. They survive across jobs so ninja can incrementally
rebuild. Wipe `hotswap-ci-persist/build` (or trigger the workflow with
`force_clean=true`) if build state goes bad.

## Register the runner (one-time, no sudo)

Grab a registration token at
<https://github.com/nirmie/llvm-project/settings/actions/runners/new>
(select Linux / x64), then:

```bash
cd /home/nisenthi/hotswap/test/actions-runner
./config.sh \
  --url https://github.com/nirmie/llvm-project \
  --token <REGISTRATION_TOKEN> \
  --name "$(hostname)-hotswap" \
  --labels self-hosted,linux,rocm,gfx950,hotswap \
  --work _work \
  --unattended \
  --ephemeral
```

`--ephemeral` means the runner auto-deregisters after one job — combined with
`./run.sh --once` below, this gives a clean "single test run then gone"
flow with no persistent daemon.

If the runner tarball is missing, download it:

```bash
cd /home/nisenthi/hotswap/test/actions-runner
curl -fSL -o runner.tgz \
  https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf runner.tgz && rm runner.tgz
```

## Run one job, then exit (no sudo, no systemd)

```bash
cd /home/nisenthi/hotswap/test/actions-runner
./run.sh --once
```

This blocks in the foreground until GitHub assigns a job, runs it, then
exits. With `--ephemeral` registration, the runner is also deregistered
from GitHub at that point. Background it with `nohup` if you want to
disconnect from the terminal:

```bash
nohup ./run.sh --once > runner.log 2>&1 &
```

## Trigger a build

After the runner is registered and `./run.sh --once` is waiting, push a
commit on the `hotswap` branch (or open a PR against `hotswap`) to fire
`hotswap-pr.yml`. The waiting runner will claim it.

Or trigger manually without code changes:

```bash
gh workflow run hotswap-pr.yml --repo nirmie/llvm-project --ref hotswap
gh run watch --repo nirmie/llvm-project
```

## Re-running

`--ephemeral` invalidates the registration after the job. To run again:

1. Grab a fresh token from the same Settings page.
2. Re-run `./config.sh` (it auto-removes the prior `.runner` / `.credentials`
   files when re-registering, or use `./config.sh remove --token <TOKEN>`
   first if it complains).
3. `./run.sh --once` again.

## First run expectations

- First job pulls `rocm/pytorch:latest` (~30 GB). Cached on the Docker
  host for subsequent runs.
- First LLVM + comgr build is cold (30–60 min). After that, the persistent
  `build/` and `ccache/` make incremental rebuilds single-digit minutes.

## OSCCI fleet reproduction (later)

When real fleet machines are available, run a long-lived runner per host
(probably via systemd) with the same labels
(`self-hosted,linux,rocm,gfx950,hotswap`). The workflow needs no change —
labels are the gate.

## Why the workflow uses `docker run --network host` (not the `container:` keyword)

GitHub Actions' `jobs.<id>.container:` keyword causes the runner to create a
dedicated bridge network (`github_network_*`) per job, and Docker allocates
that bridge the next free `/16` from its `default-address-pools`. On this
shared host that allocator pattern landed on `172.19.0.0/16`, which collided
with a developer-laptop subnet and black-holed direct SSH for an entire
afternoon. We can't fix this via `/etc/docker/daemon.json` without
restarting the Docker daemon, which would disrupt other users' running
containers.

Workaround: the workflow runs `docker run --rm --network host ...` from a
step instead of using the `container:` keyword. Host networking means no
new bridge is created — no `172.x` allocation. Trade-off: the container
sees all of the host's network interfaces, but the job only pulls/builds
and doesn't expose ports, so this is fine.

## Coexistence with the model-test harness

The end-to-end model-test harness (`harsh-amd/rocm-hotswap-testing`) runs
in its own container based on `rocm/pytorch:latest` and mounts the user's
pre-built `build/lib/libamd_comgr.so.3.3.0` at runtime. The CI's
`hotswap-ci-persist/build/` is the same kind of build tree, so a manual
debug session can point the harness at
`/home/nisenthi/hotswap/test/hotswap-ci-persist/build/lib` for
`libamd_comgr.so.3.3.0` if needed. The PR CI workflow itself does not run
the harness — that will be a separate nightly workflow added later.
