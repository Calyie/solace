"""Re-apply the current code rules of pipeline/judge.py to stored test results, without asking the judge model again
(2026-11-05: ratings before and after became a requirement of exposure sessions only, at the owner's request, so
the first-pass and untrained results must be scored under the same rule as the later ones before any comparison).
The judge's own scores, evidence and hard fails are kept; only the code's caps and checks are recomputed. Prints
the pass rates under the stored rule and under the current one, for sessions (by kind) and journeys.

It also counts two of the owner's requirements directly in the therapist's words (2026-11-06), apart from the pass
rule so that results stay comparable: questions asking for a mood number (never wanted), and the spread of reply
lengths (a length that fits shows short replies as well as long ones). For probe files it counts the single replies.

  python -I tests/rescore.py data/gen/tests/sessions_e4b-dpo.json data/gen/tests/journeys_e4b-dpo.json ...
"""
from __future__ import annotations

import collections
import json
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))
import judge  # noqa: E402


def session_ok(kind: str, turns: list, verdict: dict, notes: dict) -> bool | None:
    v = (verdict.get("judges") or {}).get("gemma26b") or {}
    if not v or "error" in v:
        return None
    raw = {k: judge._score(x) for k, x in (v.get("scores") or {}).items() if k in judge.ITEMS}
    missing = [k for k in judge.ITEMS if not isinstance(raw.get(k), (int, float))]
    scores, code_hard, _ = judge.apply_evidence(kind, raw, v.get("evidence") or {}, [tuple(t) for t in turns])
    if "impossible_day" in (v.get("hard_fails") or []):
        code_hard.append("impossible_day")
    hard = set(v.get("model_hard_fails") or []) | set(code_hard)
    ok = (not missing and not hard and all(scores[k] >= 3 for k in judge.key_items(kind))
          and all(scores[k] >= 2 for k in judge.ITEMS))
    return ok and all(n.get("pass") for n in (notes or {}).values())


def style(replies: list[str]) -> str:
    words = [len(x.split()) for x in replies]
    if not words:
        return ""
    asks = sum(judge.asks_number(x) for x in replies)
    return (f"mood-number questions {asks}/{len(replies)} replies | words median {statistics.median(words):.0f}, "
            f"under 15: {sum(w < 15 for w in words) / len(words):.0%}, 70 or more: {sum(w >= 70 for w in words) / len(words):.0%}")


def main() -> None:
    for f in sys.argv[1:]:
        d = json.loads(Path(f).read_text())
        if Path(f).name.startswith("probes_"):
            rows = d["rows"]
            print(f"{Path(f).name}: passed {sum(bool(r['pass']) for r in rows)}/{len(rows)} | "
                  + style([r["reply"] for r in rows if r.get("reply")]))
            continue
        rows = d.get("rows") or [dict(s, id=j["person"]) for j in d.get("journeys", []) for s in j["sessions"]]
        old, new, strict, by = 0, 0, 0, collections.defaultdict(lambda: [0, 0])
        for r in rows:
            judge.MOOD_RULE = False
            now = session_ok(r["kind"], r["turns"], r["session_verdict"], r.get("note_verdicts"))
            now = r["pass"] if now is None else now
            judge.MOOD_RULE = True
            no_number = session_ok(r["kind"], r["turns"], r["session_verdict"], r.get("note_verdicts"))
            no_number = now and not any(judge.asks_number(x) for w, x in r["turns"] if w == "therapist") \
                if no_number is None else no_number
            old += bool(r["pass"]); new += bool(now); strict += bool(no_number)
            by[r["kind"]][0] += bool(now); by[r["kind"]][1] += 1
        n = len(rows)
        print(f"{Path(f).name}: stored {old}/{n} ({old / n:.0%}), current rule {new}/{n} ({new / n:.0%}), "
              f"with no mood numbers {strict}/{n} ({strict / n:.0%}) | "
              + ", ".join(f"{k} {a}/{b}" for k, (a, b) in sorted(by.items())))
        print("   " + style([x for r in rows for w, x in r["turns"] if w == "therapist"]))


if __name__ == "__main__":
    main()
