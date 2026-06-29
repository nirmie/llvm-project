#!/usr/bin/env python3
"""Read a HotSwap sglang/pytorch summary.json and emit the equivalence gate
verdict. Prints "<0|1>|<overall_status>" and exits 0 (pass) / 1 (fail).

PASS = equivalence verdict passed (equivalent / numerically_close /
distributionally_equivalent). Used by docker-e2e-gemma.yml.
"""
import json
import sys

summary = json.load(open(sys.argv[1]))
eq = summary.get("equivalence", {}) or {}
# Some summaries put the verdict at top level (sglang gemma path) instead of
# under "equivalence"; accept either.
passed = eq.get("passed")
if passed is None:
    passed = summary.get("equivalence_passed")
status = eq.get("overall_status") or summary.get("equivalence_status") or "?"
ok = bool(passed)
print(f"{int(ok)}|{status}")
sys.exit(0 if ok else 1)
