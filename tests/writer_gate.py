"""The writer gate (TASKLIST A5), measured the same way on every trial: what the writer produced in a folder of
series, before any judging. No word limits are rules (owner, 2026-11-07); the length spread is measured as a signal
that replies follow the moment rather than one fixed length.

  python3 -I tests/writer_gate.py DIR/series [DIR2/series ...]
"""
from __future__ import annotations

import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
from judge import asks_number  # noqa: E402
from simulate import plan_leaked  # noqa: E402

def _grams(text: str, n: int = 4) -> set[str]:
    w = re.findall(r"[a-z0-9']+", text.lower().replace("\u2019", "'"))
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


for d in sys.argv[1:]:
    sessions = []
    for f in sorted(Path(d).glob("*.json")):
        try:
            sessions += json.loads(f.read_text()).get("sessions", [])
        except (ValueError, OSError):
            pass
    t_words, p_words, numbers, leaks, notes, think_turns, no_plan = [], [], 0, 0, 0, 0, 0
    mid, two_q, empty, ratio, stock, hundred = [], 0, 0, [], 0, 0
    replies, echo, quote_open = 0, 0, 0  # trials 10 and 11 (2026-11-07): replies opening on the person's own words
    drafts = [d for s in sessions for d in s.get("drafts", [])]
    for s in sessions:
        t = s["turns"]
        # trial 4: the therapist said three times as much as the person; in real therapy the person talks more
        tw = sum(len(x.split()) for w, x in t if w == "therapist")
        ratio.append(tw / max(1, sum(len(x.split()) for w, x in t if w == "person")))
        mid += [len(x.split()) for i, (w, x) in enumerate(t) if w == "therapist" and 0 < i < len(t) - 2]
        # the rulebook's "at most two 'It sounds' openings a session"; 0-to-100 questions outside the guided trauma
        # exercises (owner, 2026-11-07: ordinary exposure asks in words; the numbers come from the check-in)
        stock += sum(bool(re.match(r"\s*(it|that) sounds", x, re.I)) for w, x in t if w == "therapist") > 2
        if s["spec"]["kind"] not in ("written_exposure", "reliving"):
            hundred += sum(bool(re.search(r"(0|zero) to (100|a hundred)|out of (100|a hundred)", x, re.I)) and "?" in x
                           for w, x in t if w == "therapist")
        for i, (w, x) in enumerate(t):
            if w == "therapist" and i and t[i - 1][0] == "person":
                replies += 1
                first = re.split(r"(?<=[.!?,\u2014-])\s+", x.strip(), maxsplit=1)[0]
                echo += bool(_grams(first) & _grams(t[i - 1][1]))
                quote_open += bool(re.match(r'\s*["\u201c]', x))
        for w, x in s["turns"]:
            if w == "therapist":
                two_q += x.count("?") >= 2
                empty += not x.strip()
            n = len(x.split())
            if w == "therapist":
                t_words.append(n)
                numbers += asks_number(x)
                leaks += plan_leaked(x) or bool(re.search(r'^\s*\{\s*"plan"', x))
            else:
                p_words.append(n)
            notes += "stage note" in x.lower()
        if s["spec"].get("think"):
            plans = s.get("plans", [])
            think_turns += len(plans)
            no_plan += sum(not p for p in plans)

    def share(xs, f):
        return f"{sum(map(f, xs)) / max(len(xs), 1):.1%}"

    print(f"{d}: {len(sessions)} sessions, {len(t_words)} therapist turns, {len(p_words)} person turns")
    print(f"  mood-number questions {numbers}; plan text in replies {leaks}; stage notes in the conversation {notes}")
    print(f"  thinking turns {think_turns}, without a plan {no_plan} ({no_plan / max(think_turns, 1):.1%})")
    print(f"  sessions with more than two 'It/That sounds' openings {stock} ({stock / max(len(sessions), 1):.0%}); "
          f"0-to-100 questions outside exposure sessions {hundred}")
    print(f"  empty therapist turns {empty}; turns with two or more questions {two_q} "
          f"({two_q / max(len(t_words), 1):.1%})")
    print(f"  replies opening on four or more of the person's words in a row {echo / max(replies, 1):.0%} (Opus gold 11); "
          f"opening on a quotation {quote_open / max(replies, 1):.1%} (Opus 3.7)")
    if drafts:
        before = statistics.median(len(a.split()) for a, b in drafts)
        after = statistics.median(len(b.split()) for a, b in drafts)
        print(f"  spoken edit changed {len(drafts)} replies ({len(drafts) / max(len(t_words), 1):.0%}); "
              f"median words of those, before {before}, after {after}")
    if ratio:
        print(f"  therapist words per person word, per session: median {statistics.median(ratio):.2f}")
    if mid:
        print(f"  mid-session therapist words: median {statistics.median(mid)}; 15 or fewer "
              f"{share(mid, lambda n: n <= 15)}; 70 or more {share(mid, lambda n: n >= 70)}")
    if t_words:
        print(f"  therapist words: median {statistics.median(t_words)}; 5 or fewer {share(t_words, lambda n: n <= 5)}; "
              f"15 or fewer {share(t_words, lambda n: n <= 15)}; 70 or more {share(t_words, lambda n: n >= 70)}")
    if p_words:
        print(f"  person words: median {statistics.median(p_words)}; 5 or fewer {share(p_words, lambda n: n <= 5)}")
