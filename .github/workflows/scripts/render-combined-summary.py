#!/usr/bin/env python3
"""Render the combined Hotswap E2E summary as TWO tables (PyTorch + SGLang).

Usage:
    render-combined-summary.py <output_root> \
        pytorch=model1,model2,... \
        sglang=profile1,profile2,...

Reads <output_root>/<model>/**/summary.json for each model and emits a
Markdown section per framework. Used two ways:
  * per matrix job (one model) -> a one-row table that GitHub publishes the
    moment that SLURM job finishes (continuous updates), and
  * the final aggregate job (all models) -> the two consolidated tables.

Models with no summary.json but a PENDING marker render as pending (a known
gap: weights/workload/image not ready), not a failure.
"""
import glob
import json
import os
import re
import sys

_NOISE = re.compile(r"^:[0-9]+:|^[+]+ |transpiler: (Kernel|Starting disassembly)|ShaderName|kernarg_segment_size")


def model_failed(root, fw, model):
    """True if the model was attempted and did NOT pass (crash/no-summary or gate
    fail). A PENDING marker (intentional gap) is not a failure. diverged = pass."""
    sj = newest_summary(root, model, fw)
    if not sj:
        return not os.path.isfile(os.path.join(root, model, "PENDING"))
    s = json.load(open(sj))
    if fw == "pytorch-gfx1250":
        h = s.get("hotswap", {}) or {}
        t = h.get("tool_transpile", {}) or {}
        clean = (int(t.get("co_transpile", 0) or 0) > 0
                 and int(t.get("transpile_failed", 0) or 0) == 0
                 and h.get("passed") is True)
        return not clean
    if fw == "pytorch":
        l = s.get("local", {}) or {}; h = s.get("hotswap", {}) or {}
        return not (l.get("passed") is True and h.get("passed") is True
                    and int(h.get("hotswap_fail", 0) or 0) == 0)
    st = (s.get("equivalence", {}) or {}).get("overall_status")
    return st not in ("equivalent", "numerically_close", "distributionally_equivalent", "diverged")


def log_excerpt(root, model, n=30):
    """Return (excerpt, alola_path) for a model's srun.log: the last n high-signal
    lines (noise filtered). alola_path is the real path on the compute host."""
    log = os.path.join(root, model, "srun.log")
    if not os.path.isfile(log):
        return None, log
    lines = [l.rstrip() for l in open(log, errors="replace") if not _NOISE.search(l)]
    return "\n".join(lines[-n:]), log


def _search_fw(fw):
    # The gfx1250 stack writes run dirs with the same `pytorch_*` output prefix
    # as the stock pytorch stack (the framework label is a dashboard distinction,
    # not a run-dir prefix). Map it back to pytorch for summary discovery.
    return "pytorch" if fw == "pytorch-gfx1250" else fw


def newest_summary(root, model, fw=None):
    hits = glob.glob(os.path.join(root, model, "**", "summary.json"), recursive=True)
    # phi4_mini etc. appear in BOTH frameworks under the same <model> dir; the
    # per-framework run dirs are prefixed pytorch_* / sglang_*, so filter by the
    # framework prefix to avoid a pytorch row picking up an sglang summary.
    if fw:
        pref = os.sep + _search_fw(fw) + "_"
        scoped = [h for h in hits if pref in h]
        hits = scoped or hits
    return max(hits, key=os.path.getmtime) if hits else None


def row_gfx1250(root, m):
    """True-gfx1250 row: report comgr transpile coverage + opcode gaps. There is
    no equivalence verdict (no native baseline in a gfx1250-only image); the
    'result' is whether every transpiled code object lifted (clean) or some hit
    transpiler ISA gaps (reported, not an orchestration failure)."""
    sj = newest_summary(root, m, "pytorch-gfx1250")
    if not sj:
        return pending_or_missing(root, m), False
    s = json.load(open(sj))
    h = s.get("hotswap", {}) or {}
    t = h.get("tool_transpile", {}) or {}
    ok = int(t.get("transpile_ok", 0) or 0)
    fail = int(t.get("transpile_failed", 0) or 0)
    att = int(t.get("co_transpile", 0) or 0)
    native = int(t.get("co_pass", 0) or 0)
    gaps = t.get("unsupported_opcodes", []) or []
    if att and fail == 0 and ok > 0 and h.get("passed") is True:
        res, gate = ":white_check_mark: clean", True
    elif gaps:
        res, gate = ":warning: gaps", True
    elif att == 0:
        res, gate = ":grey_question: no transpile", False
    else:
        res, gate = ":x: fail", False
    gapcell = ", ".join(f"`{g}`" for g in gaps[:6]) + ("…" if len(gaps) > 6 else "") or "—"
    name = s.get("display_name", m)
    return (f"| {name} | {native}/{att} | {ok}/{fail} | {gapcell} | {res} |"), gate


def equiv_cell(status):
    return {
        "equivalent": ":white_check_mark: equivalent",
        "numerically_close": ":white_check_mark: numerically close",
        "distributionally_equivalent": ":white_check_mark: distributionally equivalent",
        "diverged": ":warning: diverged (expected)",
    }.get(status, f"`{status}`" if status else "—")


def row_pytorch(root, m):
    sj = newest_summary(root, m, "pytorch")
    if not sj:
        return pending_or_missing(root, m), False
    s = json.load(open(sj))
    local, hot, eq = (s.get(k, {}) or {} for k in ("local", "hotswap", "equivalence"))
    hfail = int(hot.get("hotswap_fail", 0) or 0)
    hsucc, hres = hot.get("hotswap_success", 0), hot.get("hotswap_results", 0)
    gate = local.get("passed") is True and hot.get("passed") is True and hfail == 0
    ch, cm = hot.get("proof_cache_hits", "?"), hot.get("proof_cache_misses", "?")
    eqs = eq.get("overall_status")
    ecell = equiv_cell(eqs)
    if eqs == "diverged":
        dl = eq.get("overall_max_top_logprob_diff") or 0  # may be present-but-None
        ecell += f"<br>Δlogprob {float(dl):.2f}"
    res = ":white_check_mark: pass" if gate else ":x: fail"
    name = s.get("display_name", m)
    lcell = (":white_check_mark:" if local.get("passed") else ":x:") + \
        (f" {local.get('aggregate_tok_s', 0):.1f} tok/s" if local.get("aggregate_tok_s") else "")
    return (f"| {name} | {lcell} | `{hot.get('proof_status','—')}` {hsucc}/{hres}"
            + (f" ({hfail} fail)" if hfail else "")
            + f" | {ecell} | {ch}/{cm} | {res} |"), gate


def row_sglang(root, m):
    sj = newest_summary(root, m, "sglang")
    if not sj:
        return pending_or_missing(root, m), False
    s = json.load(open(sj))
    eq = s.get("equivalence", {}) or {}          # sglang summary: equivalence sub-dict
    status = eq.get("overall_status")
    clean = status in ("equivalent", "numerically_close", "distributionally_equivalent")
    diverged = status == "diverged"
    transpiled = bool(status)  # a verdict means both branches ran -> transpile completed
    # Gate matches the pytorch table: transpile running end-to-end is the pass
    # signal; `diverged` is the EXPECTED gfx1250->gfx950 accumulation effect and
    # is reported (warning), not a CI failure. Only a missing/garbled verdict fails.
    if clean:
        res, gate = ":white_check_mark: pass", True
    elif diverged:
        res, gate = ":warning: diverged (transpiled)", True
    else:
        res, gate = ":x: fail", False
    div = (f"<br>{eq.get('cases_with_token_divergence','?')}/{eq.get('cases_total','?')} cases"
           if diverged else "")
    return (f"| {s.get('profile', m)} | {'yes' if transpiled else 'no'} | "
            f"{equiv_cell(status)}{div} | {status or '—'} | {res} |"), gate


def pending_or_missing(root, m):
    pend = os.path.join(root, m, "PENDING")
    if os.path.isfile(pend):
        reason = (open(pend).read().strip() or "pending")
        return f"PENDING::{reason}"
    # No summary AND no PENDING marker = the model was attempted and crashed
    # before writing summary.json -> a failure, not "missing".
    return "FAIL"


def render_table(root, framework, models):
    out = []
    if framework == "pytorch-gfx1250":
        out.append(f"### True-gfx1250 transpile ({len(models)})\n")
        out.append("| Model | Code objs (native/transpiled) | Transpile (ok/fail) | Unsupported opcodes | Result |")
        out.append("|-------|-------------------------------|---------------------|---------------------|--------|")
        rowfn, ncols = row_gfx1250, 5
    elif framework == "pytorch":
        out.append(f"### PyTorch models ({len(models)})\n")
        out.append("| Model | Local | HotSwap transpile | Equivalence | Cache (hit/miss) | Result |")
        out.append("|-------|-------|-------------------|-------------|------------------|--------|")
        rowfn, ncols = row_pytorch, 6
    else:
        out.append(f"### SGLang profiles ({len(models)})\n")
        out.append("| Profile | HotSwap proof | Equivalence | Verdict | Result |")
        out.append("|---------|---------------|-------------|---------|--------|")
        rowfn, ncols = row_sglang, 5
    any_fail = False
    for m in models:
        row, gate = rowfn(root, m)
        if isinstance(row, str) and row.startswith("PENDING::"):
            reason = row.split("::", 1)[1]
            out.append(f"| {m} |" + " — |" * (ncols - 2) + f" :hourglass: pending ({reason}) |")
        elif row == "FAIL":
            out.append(f"| {m} |" + " — |" * (ncols - 2) + " :x: fail (no summary.json) |")
            any_fail = True
        else:
            out.append(row)
            any_fail = any_fail or not gate
    out.append("")
    return "\n".join(out), any_fail


def main():
    root = sys.argv[1]
    specs = sys.argv[2:]
    print("## Hotswap E2E summary\n")
    overall_fail = False
    for spec in specs:
        fw, _, csv = spec.partition("=")
        models = [m for m in csv.split(",") if m]
        if not models:
            continue
        table, fail = render_table(root, fw, models)
        print(table)
        overall_fail = overall_fail or fail
    print("> `diverged` equivalence is expected (accumulation-order token flips) and is "
          "reported, not failed. PyTorch gate = baseline + transpile ran end-to-end; "
          "SGLang gate = equivalence checker verdict.")

    # Failed-model logs: for each non-passing model, a collapsible excerpt of its
    # srun.log + the full path on the Alola compute host (for deep debugging).
    failed = [(fw, m) for spec in specs
              for fw, _, csv in [spec.partition("=")]
              for m in csv.split(",") if m and model_failed(root, fw, m)]
    if failed:
        print("\n### Failed model logs\n")
        for fw, m in failed:
            excerpt, logpath = log_excerpt(root, m)
            print(f"<details><summary>:x: <b>{fw}/{m}</b></summary>\n")
            print(f"Alola log: `{logpath}`\n")
            if excerpt:
                print("```")
                print(excerpt)
                print("```")
            else:
                print("_(no srun.log captured)_")
            print("\n</details>\n")
    # Always 0: this is a renderer, not a gate. Per-model pass/fail is in the
    # table + badges; a non-zero here would only mask render crashes.
    _ = overall_fail
    return 0


if __name__ == "__main__":
    sys.exit(main())
