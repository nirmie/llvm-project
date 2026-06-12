#!/usr/bin/env python3
"""Emit one shields.io-endpoint JSON per (framework, model) for the README
scoreboard (rocm-libraries-style dynamic badges).

Usage:
    emit-status-badges.py <output_root> <out_dir> \
        pytorch=model1,model2,... \
        sglang=profile1,profile2,...

Writes <out_dir>/<framework>/<model>.json with the shields endpoint schema:
    {"schemaVersion":1, "label":"", "message":"pass", "color":"brightgreen"}

The aggregate job pushes <out_dir> to the orphan `ci-status` branch; the README
badges point shields.io at the raw JSON on that branch, so per-model status
updates live without committing to the source history.

Verdict contract MIRRORS render-combined-summary.py (keep them in sync):
  * pytorch gate  = local.passed AND hotswap.passed AND hotswap_fail==0.
                    Within a passing gate, equivalence `diverged` is surfaced
                    as yellow (expected accumulation-order flips), clean as green.
  * sglang gate   = equivalence verdict present; clean=green, diverged=yellow,
                    else red.
  * no summary.json but a PENDING marker -> grey "pending" (weights/image gap),
    not a failure; no summary and no marker -> red "missing".
"""
import glob
import json
import os
import sys

COLOR = {
    "pass": "brightgreen",
    "transpiled": "brightgreen",
    "diverged": "yellow",
    "gaps": "yellow",
    "fail": "red",
    "pending": "lightgrey",
    "missing": "red",
}
CLEAN = ("equivalent", "numerically_close", "distributionally_equivalent")


def newest_summary(root, model, fw=None):
    hits = glob.glob(os.path.join(root, model, "**", "summary.json"), recursive=True)
    # phi4_mini etc. live in BOTH frameworks under the same <model> dir; the
    # per-framework run dirs are prefixed pytorch_* / sglang_*, so filter by the
    # framework so the pytorch badge doesn't pick up the sglang summary (which
    # lacks local/hotswap keys -> spurious "fail").
    if fw:
        # gfx1250 runs share the pytorch_* run-dir prefix (the framework is a
        # dashboard label, not a run-dir prefix); map it back for discovery.
        search_fw = "pytorch" if fw == "pytorch-gfx1250" else fw
        pref = os.sep + search_fw + "_"
        scoped = [h for h in hits if pref in h]
        hits = scoped or hits
    return max(hits, key=os.path.getmtime) if hits else None


def classify_gfx1250(root, model):
    sj = newest_summary(root, model, "pytorch-gfx1250")
    if not sj:
        return pending_state(root, model)
    s = json.load(open(sj))
    h = s.get("hotswap", {}) or {}
    t = h.get("tool_transpile", {}) or {}
    att = int(t.get("co_transpile", 0) or 0)
    fail = int(t.get("transpile_failed", 0) or 0)
    ok = int(t.get("transpile_ok", 0) or 0)
    if att and fail == 0 and ok > 0 and h.get("passed") is True:
        return "transpiled"
    if t.get("unsupported_opcodes"):
        return "gaps"
    return "fail"


def pending_state(root, model):
    """No summary.json: a PENDING marker = a known/intentional gap (weights or
    workload not ready) -> grey 'pending'. Otherwise the model WAS attempted and
    crashed before writing a summary -> red 'fail' (not 'missing', which wrongly
    implies it was never run)."""
    if os.path.isfile(os.path.join(root, model, "PENDING")):
        return "pending"
    return "fail"


def classify_pytorch(root, model):
    sj = newest_summary(root, model, "pytorch")
    if not sj:
        return pending_state(root, model)
    s = json.load(open(sj))
    local = s.get("local", {}) or {}
    hot = s.get("hotswap", {}) or {}
    eq = s.get("equivalence", {}) or {}
    hfail = int(hot.get("hotswap_fail", 0) or 0)
    gate = local.get("passed") is True and hot.get("passed") is True and hfail == 0
    if not gate:
        return "fail"
    return "diverged" if eq.get("overall_status") == "diverged" else "pass"


def classify_sglang(root, model):
    sj = newest_summary(root, model, "sglang")
    if not sj:
        return pending_state(root, model)
    s = json.load(open(sj))
    status = (s.get("equivalence", {}) or {}).get("overall_status")
    if status in CLEAN:
        return "pass"
    if status == "diverged":
        return "diverged"
    return "fail"


def gfx1250_badge_message(root, model, state):
    """Badge text for the gfx1250 column. The README shows only the message, so
    surface the actual blocking opcode(s) when the transpile hit ISA gaps --
    e.g. 'gaps: v_cvt_f16_i16' or 'gaps: v_cvt_f16_i16 +2'. Other states render
    as the plain state string."""
    if state != "gaps":
        return state
    sj = newest_summary(root, model, "pytorch-gfx1250")
    ops = []
    if sj:
        t = (json.load(open(sj)).get("hotswap", {}) or {}).get("tool_transpile", {}) or {}
        ops = t.get("unsupported_opcodes", []) or []
    if not ops:
        return "gaps"
    head = ops[0]
    return f"gaps: {head}" + (f" +{len(ops) - 1}" if len(ops) > 1 else "")


def write_badge(out_dir, framework, model, state, message=None):
    d = os.path.join(out_dir, framework)
    os.makedirs(d, exist_ok=True)
    badge = {
        "schemaVersion": 1,
        "label": "",
        "message": message if message is not None else state,
        "color": COLOR.get(state, "lightgrey"),
    }
    with open(os.path.join(d, f"{model}.json"), "w") as f:
        json.dump(badge, f)
    return badge["message"]


def main():
    root, out_dir = sys.argv[1], sys.argv[2]
    classify = {
        "pytorch": classify_pytorch,
        "pytorch-gfx1250": classify_gfx1250,
        "sglang": classify_sglang,
    }
    for spec in sys.argv[3:]:
        fw, _, csv = spec.partition("=")
        if fw not in classify:
            continue
        for model in (m for m in csv.split(",") if m):
            state = classify[fw](root, model)
            message = (
                gfx1250_badge_message(root, model, state)
                if fw == "pytorch-gfx1250" else None
            )
            shown = write_badge(out_dir, fw, model, state, message)
            print(f"{fw}/{model}: {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
