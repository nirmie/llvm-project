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
    "diverged": "yellow",
    "fail": "red",
    "pending": "lightgrey",
    "missing": "red",
}
CLEAN = ("equivalent", "numerically_close", "distributionally_equivalent")


def newest_summary(root, model):
    hits = glob.glob(os.path.join(root, model, "**", "summary.json"), recursive=True)
    return max(hits, key=os.path.getmtime) if hits else None


def pending_state(root, model):
    """No summary.json: distinguish a known gap (PENDING marker) from missing."""
    if os.path.isfile(os.path.join(root, model, "PENDING")):
        return "pending"
    return "missing"


def classify_pytorch(root, model):
    sj = newest_summary(root, model)
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
    sj = newest_summary(root, model)
    if not sj:
        return pending_state(root, model)
    s = json.load(open(sj))
    status = (s.get("equivalence", {}) or {}).get("overall_status")
    if status in CLEAN:
        return "pass"
    if status == "diverged":
        return "diverged"
    return "fail"


def write_badge(out_dir, framework, model, state):
    d = os.path.join(out_dir, framework)
    os.makedirs(d, exist_ok=True)
    badge = {
        "schemaVersion": 1,
        "label": "",
        "message": state,
        "color": COLOR.get(state, "lightgrey"),
    }
    with open(os.path.join(d, f"{model}.json"), "w") as f:
        json.dump(badge, f)
    return state


def main():
    root, out_dir = sys.argv[1], sys.argv[2]
    classify = {"pytorch": classify_pytorch, "sglang": classify_sglang}
    for spec in sys.argv[3:]:
        fw, _, csv = spec.partition("=")
        if fw not in classify:
            continue
        for model in (m for m in csv.split(",") if m):
            state = write_badge(out_dir, fw, model, classify[fw](root, model))
            print(f"{fw}/{model}: {state}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
