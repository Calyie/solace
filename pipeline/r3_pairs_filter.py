"""Round 3 (2026-11-19): preference pairs aimed at what the tests found the SFT model still does.

At each context from the judged hand-written sessions the model's own reply was collected (r3_rejected.py against the
served SFT model). A pair is kept only when the model's reply shows a fault the hand-written reply does not:

  question_end   its reply ends in a question and the hand-written one does not (16 simulated hard users, 2026-11-19:
                 54 percent of the first candidate's replies ended in a question; the hand-written sessions, 27)
  hand_back      it hands the work back ("What do you think", "How does that sound", "Tell me ...", "only you can")
  deflect        it puts the answer off or says it is not there to give one ("a separate problem", "I'm not going to")
  form           lists, bold or headings in something that may be read aloud
  banned         time talk, the maker's name, a body question

  python -I r3_pairs_filter.py --own rej_own.jsonl --faults fault_pairs.jsonl --out pairs.jsonl
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from r3_build import BODY_Q, LIST_LINE, MAKER, MARKDOWN, TIME_TALK  # noqa: E402

HAND_BACK = re.compile(r"(what do you think|how does that sound|how do you feel about that|what feels (most )?(useful|right)|"
                       r"what would you like to|only you can (decide|make|weigh)|that'?s a decision only you|"
                       r"what comes to mind|where would you like to (start|begin))", re.I)
TELL_ME = re.compile(r"(^|[.!?]\s+)(tell me|give me|walk me through|describe)\b[^.?!]*[.?!]?\s*$", re.I)
DEFLECT = re.compile(r"(i'?m not going to (tell|give)|i can'?t tell you what|not here to give you|a separate problem we|"
                     r"we'?ll (tackle|get to|come back to) (that|it) (in a few weeks|later|next time|another day)|"
                     r"before we talk about what to do)", re.I)


def faults(text: str) -> list[str]:
    t = text.strip()
    out = []
    if t.endswith("?"):
        out.append("question_end")
    if HAND_BACK.search(t) or TELL_ME.search(t):
        out.append("hand_back")
    if DEFLECT.search(t):
        out.append("deflect")
    if LIST_LINE.search(t) or MARKDOWN.search(t):
        out.append("form")
    if TIME_TALK.search(t) or MAKER.search(t) or BODY_Q.search(t):
        out.append("banned")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--own", nargs="+", required=True, help="pairs whose rejected side is a model's own reply")
    ap.add_argument("--faults", help="the fixed fault pairs from r3_build.py (kept as they are)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    kept, seen = [], Counter()
    for f in a.own:
        for line in Path(f).read_text().splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            good, bad = r["chosen"][0]["content"], r["rejected"][0]["content"]
            why = [w for w in faults(bad) if w not in faults(good)]
            seen["contexts"] += 1
            if not why:
                continue
            for w in why:
                seen[w] += 1
            kept.append({**r, "why": "+".join(why)})
    n_fault = 0
    if a.faults:
        for line in Path(a.faults).read_text().splitlines():
            if line.strip():
                kept.append(json.loads(line))
                n_fault += 1
    Path(a.out).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in kept))
    print(json.dumps({**seen, "kept_own": len(kept) - n_fault, "fixed_fault_pairs": n_fault, "pairs": len(kept)}))


if __name__ == "__main__":
    main()
