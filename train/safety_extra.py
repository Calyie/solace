"""Extra training lines for the safety classifier (train/safety_clf.py --extra), from our own generated sessions and
from CACTUS, so the classifier also learns how people talk in this app.

- Risk: in a session where risk was required to come out, the person's message just before the therapist's safety
  response (the judges quote that response as evidence, and the quote is checked against the session) is labelled
  self_harm. Other messages in those sessions are left out, since their label is unclear.
- Safe: messages from sessions with no risk in the profile and no required risk event (capped), and CACTUS client
  lines that the code risk pattern does not flag.

Usage (pod): python -I train/safety_extra.py --gen data/gen/main --profiles data/gen/profiles.jsonl --cactus data/raw/LangAGI-Lab__cactus/cactus.json \
                 --out data/gen/main/safety_extra.jsonl [--max-safe 4000]
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
import judge  # noqa: E402

RISK_EVENT = re.compile(r"suicid|wake up|cut yourself|self-harm", re.I)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen", required=True)
    ap.add_argument("--profiles", required=True)
    ap.add_argument("--cactus", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-safe", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=5)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    gen = Path(a.gen)
    risk_of = {}
    for line in Path(a.profiles).read_text().splitlines():
        if line.strip():
            p = json.loads(line)
            risk_of[p["id"]] = p.get("risk", "none")
    evidence: dict[str, list[str]] = {}  # session key -> the judges' safety_response quotes (checked below)
    for vf in (gen / "verdicts").glob("*.jsonl"):
        for line in vf.read_text().splitlines():
            if line.strip():
                v = json.loads(line)
                q = (v.get("evidence") or {}).get("safety_response")
                if q and q.strip().upper() != "NONE":
                    evidence.setdefault(v["key"], []).append(q)
    risk_rows, safe_rows = [], []
    for f in sorted((gen / "series").glob("*.json")):
        rec = json.loads(f.read_text())
        for i, s in enumerate(rec["sessions"]):
            key, turns = f"{rec['profile']}{rec.get('suffix', '')}#{i}", s["turns"]
            if RISK_EVENT.search(s.get("required_event", "")):
                quotes = [q for q in evidence.get(key, []) if judge.quoted(q, turns)]
                if not quotes:
                    continue
                qn = judge._norm(quotes[0])
                for k, (w, t) in enumerate(turns):
                    if w == "therapist" and qn in judge._norm(t) and k > 0 and turns[k - 1][0] == "person":
                        ctx = turns[k - 2][1] if k >= 2 else ""
                        risk_rows.append({"context": ctx, "text": turns[k - 1][1], "label": "self_harm", "group": key})
                        break
            elif not s.get("required_event") and risk_of.get(rec["profile"], "none").lower().startswith("none"):
                for k, (w, t) in enumerate(turns):
                    if w == "person":
                        safe_rows.append({"context": turns[k - 1][1] if k else "", "text": t, "label": "safe", "group": key})
    cactus = json.loads(Path(a.cactus).read_text())
    for r in cactus:
        for line in re.findall(r"Client:\s*(.+)", r.get("dialogue", "")):
            if not judge.RISK.search(line):
                safe_rows.append({"context": "", "text": line.strip(), "label": "safe", "group": "cactus:" + line[:30]})
    rng.shuffle(safe_rows)
    rows = risk_rows + safe_rows[: a.max_safe]
    Path(a.out).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"risk lines {len(risk_rows)}, safe lines {min(len(safe_rows), a.max_safe)} of {len(safe_rows)} -> {a.out}")


if __name__ == "__main__":
    main()
