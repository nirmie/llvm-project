#!/usr/bin/env python3
"""Aggregate per-model HotSwap CI result JSONs into ONE consolidated markdown
summary and append it to $GITHUB_STEP_SUMMARY (falls back to stdout).

Each per-model result JSON (written by run-sglang-model.sh / run-pytorch-model.sh
and collected here via download-artifact) has the shape:

    {
      "lane":   "SGLang E2E gfx950",   # grouping key / table section
      "model":  "qwen3_0_6b",          # model leg name
      "state":  "pass|diverged|fail|skip",
      "detail": "overall_status=... / verdict string"
    }

State -> emoji map:
    pass     -> :white_check_mark:  (gate ok AND numerically equivalent/close)
    diverged -> :warning:           (gate ok BUT numerical divergence)
    fail     -> :x:                 (gate failed / crashed / no verdict)
    skip     -> :fast_forward:      (weights absent / lane skipped)

Usage: render-summary.py <dir-with-result-json-files>
Missing/empty dir is handled gracefully (renders a "no results" note).
"""
import glob
import json
import os
import sys

EMOJI = {
    "pass":     ":white_check_mark:",
    "diverged": ":warning:",
    "fail":     ":x:",
    "skip":     ":fast_forward:",
}
# Stable lane ordering; unknown lanes are appended alphabetically after these.
LANE_ORDER = [
    "SGLang E2E gfx950",
    "SGLang E2E gfx942",
    "Pytorch E2E gfx950",
]


def load_results(root):
    results = []
    for path in sorted(glob.glob(os.path.join(root, "**", "*.json"), recursive=True)):
        try:
            with open(path) as fh:
                obj = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(obj, dict):
            continue
        obj.setdefault("lane", "Unknown lane")
        obj.setdefault("model", os.path.basename(path))
        state = obj.get("state", "fail")
        if state not in EMOJI:
            state = "fail"
        obj["state"] = state
        obj.setdefault("detail", "")
        results.append(obj)
    return results


def lane_sort_key(lane):
    return (LANE_ORDER.index(lane) if lane in LANE_ORDER else len(LANE_ORDER), lane)


def render(results):
    out = []
    out.append("# HotSwap PR CI — Model Results")
    out.append("")
    out.append(
        "Legend: :white_check_mark: pass &nbsp; :warning: ran but numerically "
        "diverged (not gated) &nbsp; :x: failed &nbsp; :fast_forward: skipped"
    )
    out.append("")

    if not results:
        out.append(
            "> No model result artifacts were found. The E2E lanes were likely "
            "skipped (e.g. `build + lit` failed) or produced no results."
        )
        return "\n".join(out) + "\n"

    # Group by lane.
    lanes = {}
    for r in results:
        lanes.setdefault(r["lane"], []).append(r)

    for lane in sorted(lanes, key=lane_sort_key):
        rows = sorted(lanes[lane], key=lambda r: r["model"])
        counts = {k: 0 for k in EMOJI}
        for r in rows:
            counts[r["state"]] += 1
        tally = (
            f"{counts['pass']} pass / {counts['diverged']} diverged / "
            f"{counts['fail']} fail / {counts['skip']} skip"
        )
        out.append(f"## {lane}")
        out.append("")
        out.append(f"_{len(rows)} models — {tally}_")
        out.append("")
        out.append("| Model | Result | Equivalence / Detail |")
        out.append("| --- | :---: | --- |")
        for r in rows:
            emoji = EMOJI[r["state"]]
            detail = str(r.get("detail", "")).replace("|", "\\|").replace("\n", " ")
            label = r["state"]
            out.append(f"| `{r['model']}` | {emoji} {label} | {detail} |")
        out.append("")

    return "\n".join(out) + "\n"


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    results = load_results(root)
    md = render(results)
    dest = os.environ.get("GITHUB_STEP_SUMMARY")
    if dest:
        with open(dest, "a") as fh:
            fh.write(md)
    sys.stdout.write(md)


if __name__ == "__main__":
    main()
