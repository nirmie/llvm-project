#!/usr/bin/env python3
"""Render PyTorch HotSwap E2E summary.json files as a GitHub Actions
step-summary (Markdown). Usage:

    render-e2e-summary.py <output_root> <model_stem> [<model_stem> ...]

For each model it looks for the newest
<output_root>/<model>/**/summary.json and emits one table row plus a
collapsible <details> with that run's summary.md.

Metric choices (per the runner's real summary schema):
  * Local      -- did the unmodified gfx950 baseline run?  (local.passed)
  * HotSwap    -- did the gfx1250->target transpile + run succeed?
                  (hotswap.proof_status + hotswap_success/hotswap_results)
  * Equivalence-- teacher-forced verdict (equivalence.overall_status):
                  'equivalent' / 'distributionally_equivalent' are clean,
                  'diverged' is EXPECTED for gfx1250->gfx94x/gfx950
                  (accumulation-order differences flip tokens) and is
                  reported, not failed.
  * Cache      -- transpile cache hits/misses (cold vs warm run).

CI gate (the 'Result' column) is local.passed AND hotswap.passed AND
hotswap_fail==0 -- i.e. the compiler pipeline ran the model end to end.
Equivalence is shown as a separate signal, not part of the gate, because
divergence is currently expected.
"""
import glob
import json
import os
import sys


def newest_summary(root: str, model: str):
    hits = glob.glob(os.path.join(root, model, "**", "summary.json"), recursive=True)
    if not hits:
        return None
    return max(hits, key=os.path.getmtime)


def fmt_equiv(status: str) -> str:
    return {
        "equivalent": ":white_check_mark: equivalent",
        "distributionally_equivalent": ":white_check_mark: distributionally equivalent",
        "diverged": ":warning: diverged (expected)",
    }.get(status, f"`{status}`")


def main() -> int:
    root, models = sys.argv[1], sys.argv[2:]
    out = ["## PyTorch HotSwap E2E summary", ""]
    out.append("| Model | Local | HotSwap transpile | Equivalence | Cache (hit/miss) | Result |")
    out.append("|-------|-------|-------------------|-------------|------------------|--------|")
    details = []
    any_fail = False
    for m in models:
        sj = newest_summary(root, m)
        if not sj:
            # A model the run-script skipped (no config / no weights) leaves a
            # PENDING marker; show it as a known gap, not a failure, so the
            # summary covers every model-support-plan group.
            pend = os.path.join(root, m, "PENDING")
            if os.path.isfile(pend):
                reason = open(pend).read().strip() or "pending"
                out.append(f"| {m} | — | — | — | — | :hourglass: pending ({reason}) |")
            else:
                out.append(f"| {m} | — | — | — | — | :x: no summary.json |")
                any_fail = True
            continue
        s = json.load(open(sj))
        local = s.get("local", {}) or {}
        hot = s.get("hotswap", {}) or {}
        eq = s.get("equivalence", {}) or {}

        local_ok = local.get("passed") is True
        hot_ok = hot.get("passed") is True
        hfail = hot.get("hotswap_fail", 0) or 0
        hsucc = hot.get("hotswap_success", 0) or 0
        hres = hot.get("hotswap_results", hsucc) or 0
        ch = hot.get("proof_cache_hits", hot.get("cache_debug_hits", 0))
        cm = hot.get("proof_cache_misses", hot.get("cache_debug_misses", 0))

        local_cell = (":white_check_mark:" if local_ok else ":x:") + \
            (f" {local.get('aggregate_tok_s', 0):.1f} tok/s" if local.get("aggregate_tok_s") else "")
        hot_cell = f"`{hot.get('proof_status', '—')}` {hsucc}/{hres}"
        if hfail:
            hot_cell += f" ({hfail} fail)"
        eq_cell = fmt_equiv(eq.get("overall_status", "—")) if eq.get("overall_status") else "n/a"
        if eq.get("overall_status") == "diverged":
            eq_cell += (f"<br>{eq.get('cases_with_token_divergence', '?')}/"
                        f"{eq.get('cases_total', '?')} cases, "
                        f"Δlogprob {eq.get('overall_max_top_logprob_diff', 0):.2f}")

        gate_ok = local_ok and hot_ok and hfail == 0
        any_fail = any_fail or not gate_ok
        result = ":white_check_mark: pass" if gate_ok else ":x: fail"
        out.append(f"| {s.get('display_name', m)} | {local_cell} | {hot_cell} | "
                   f"{eq_cell} | {ch}/{cm} | {result} |")

        md = os.path.join(os.path.dirname(sj), "summary.md")
        if os.path.isfile(md):
            details.append((s.get("display_name", m), open(md).read()))

    out.append("")
    out.append("> **Result** gate = baseline ran **and** gfx1250→target transpile ran the "
               "model end-to-end. `diverged` equivalence is expected (accumulation-order "
               "token flips) and is reported separately, not failed.")
    for name, body in details:
        out.append(f"\n<details><summary>{name} — full summary.md</summary>\n\n{body}\n</details>")

    print("\n".join(out))
    return 1 if any_fail else 0


if __name__ == "__main__":
    sys.exit(main())
