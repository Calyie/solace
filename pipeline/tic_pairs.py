"""The mood-rating reflex (2026-11-06 diagnosis): in 8 of the 12 probes the first-pass model got worse on, it broke
off what the person was saying to ask "How are you feeling right now, on a scale of 0 to 10?" (after a bereavement,
a new habit, a value, a goal change). The old rulebook asked for ratings at the start and end of every session, and
the model over-learned it; the owner had already called it unnatural. Preference pairs from the natural-length
sessions (training people only): at a moment past the opening, the kept reply (which carries on with what the person
said) against the same opening sentence followed by a mood rating. Owner, 2026-11-06 04:25: the 0-to-10 mood question
comes out everywhere, openings included, so openings that ask for one become pairs too: the same opening with the
number question rewritten as a natural question is preferred.

  python -I pipeline/tic_pairs.py --sft data/gen/v3/kept/sft.jsonl --out data/gen/v3/kept/tic_pairs.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path

RATING = re.compile(r"\b(0|zero) (to|and) ?(10|ten)\b|\bout of (10|ten)\b|\bscale of\b", re.I)
ASKS = ["How are you feeling right now, on a scale of 0 to 10?", "On a scale of 0 to 10, how are you feeling right now?",
        "Before we go on, how would you rate your mood from 0 to 10?", "How are you feeling at the moment, from 0 to 10?"]


def first_sentence(text: str) -> str:
    m = re.match(r"(.+?[.!?])(\s|$)", text.strip())
    return (m.group(1) if m else text.strip()).strip()


MOOD_Q = re.compile(r"(,? (on a scale )?(of |from )?(0|zero) (to|and) ?(10|ten)\b( where (10|ten) is [^?.,]*)?|,? out of (10|ten))", re.I)


def natural(opening: str) -> str | None:
    """The same opening with the 0-to-10 part removed from its mood question ("How are you today, from 0 to 10?" ->
    "How are you today?"); None when nothing natural is left."""
    new = re.sub(r"\b(on|using) a scale (of|from) (0|zero) (to|and) ?(10|ten)( where (10|ten) is [^?.,]*)?, *(\w)",
                 lambda x: x.group(8).upper(), opening, flags=re.I)  # "On a scale of 0 to 10, how is..." -> "How is..."
    new = MOOD_Q.sub("", new)
    new = re.sub(r"\s+\?", "?", re.sub(r"\s{2,}", " ", new)).strip()
    if new == opening.strip() or RATING.search(new) or "?" not in new or re.search(r"\brat(e|ing)\b|\bput\b|\bnumber\b", new, re.I):
        return None
    return new


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-session", type=int, default=3)
    ap.add_argument("--cap", type=int, default=500)
    ap.add_argument("--seed", type=int, default=21)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    out = []
    for r in map(json.loads, open(a.sft)):
        if r.get("task") != "session":
            continue
        m = r["messages"]
        first = [k for k in range(2, len(m)) if m[k]["role"] == "assistant"][:2]
        for k in first:  # openings that ask for a mood number: the natural question wins
            nat = natural(m[k]["content"]) if RATING.search(m[k]["content"]) else None
            if nat:
                out.append({"id": f"{r['id']}@{k}#open", "why": "mood_rating_opening", "source": "fault:mood_rating",
                            "prompt": m[:k], "chosen": [{"role": "assistant", "content": nat}],
                            "rejected": [{"role": "assistant", "content": m[k]["content"]}]})
        th = [k for k in range(2, len(m)) if m[k]["role"] == "assistant"][2:]
        rng.shuffle(th)
        for k in th[: a.per_session]:
            good = m[k]["content"]
            if RATING.search(good) or len(good.split()) < 8:
                continue
            bad = f"{first_sentence(good)} {rng.choice(ASKS)}"
            if bad.strip() == good.strip():
                continue
            out.append({"id": f"{r['id']}@{k}#tic", "why": "mood_rating_reflex", "source": "fault:mood_rating",
                        "prompt": m[:k], "chosen": [{"role": "assistant", "content": good}],
                        "rejected": [{"role": "assistant", "content": bad}]})
    rng.shuffle(out)
    out = out[: a.cap]
    Path(a.out).write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in out))
    print(len(out), "pairs")


if __name__ == "__main__":
    main()
