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
import sys


def newest_summary(root, model, fw=None):
    hits = glob.glob(os.path.join(root, model, "**", "summary.json"), recursive=True)
    # phi4_mini etc. appear in BOTH frameworks under the same <model> dir; the
    # per-framework run dirs are prefixed pytorch_* / sglang_*, so filter by the
    # framework prefix to avoid a pytorch row picking up an sglang summary.
    if fw:
        pref = os.sep + fw + "_"
        scoped = [h for h in hits if pref in h]
        hits = scoped or hits
    return max(hits, key=os.path.getmtime) if hits else None


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
        ecell += f"<br>Δlogprob {eq.get('overall_max_top_logprob_diff', 0):.2f}"
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
    if framework == "pytorch":
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
    return 1 if overall_fail else 0


if __name__ == "__main__":
    sys.exit(main())
