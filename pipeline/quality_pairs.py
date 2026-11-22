"""Second training pass, therapy quality (owner, 2026-11-05 20:40: the safety level is good now; the top priority is
therapy sessions that are very advanced, meet every goal we defined, and pass at least 80 percent of the practice
sessions and journeys). The first-pass failures, by judge reason (E4B, 102 of 180 sessions; journeys alike): no
safety question in a first session 39 (a session goal in the rulebook, so it stays here), weak homework 21, notes
listing plans the person never agreed to 16, little real work done (no rating before and after, no practice) 12,
memory not used 4, unsafe reply to a risk hint 2 (7 for E2B).

Preference pairs at the moments that decide those scores, built from the kept training sessions (training people
only), with the rejected reply written by the model being trained at the same moment; a pair is kept only when the
model's own reply misses what the kept reply does:
  screen    first session: the turn that asks about safety
  rating    (not used by default; owner, 2026-11-05: a rating at the start and end of every session is unnatural;
            ratings belong to exposure work) a 0-10 or 0-100 rating at the start, and again near the end
  homework  near the end of a first or weekly session: one concrete task agreed for the coming days
  memory    the opening turns of a later session: following up on what was said or agreed last time
  practice  a daily check-in or practice session: starting the practice together
  risk      the turn after the person's first risk message: asking kindly and directly about it (small share)
  overask   the opposite guard (owner: do not keep asking about safety; it can be triggering, annoying or
            insulting): a moment with no sign of risk where the model asks about safety and the kept reply does not
  note      the kept note against the same note with a plan item the person never agreed to (synthetic)
plus a random sample of the first pass's pairs, so the rest of what it taught is held in place.

  python -I pipeline/quality_pairs.py --model-url http://localhost:8002 --model e4b-dpo --out data/gen/main/kept/quality_pairs_e4b.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from judge import SAFETY_LANG, risk_turn  # noqa: E402
from llm import Chat  # noqa: E402

RATING = re.compile(r"\b0 (to|and|-) ?(10|100)\b|\bout of (10|ten|100)\b|\bscale of\b|\bfrom 0\b|\brate\b", re.I)
HOMEWORK = re.compile(r"this (coming )?week|before (we|our) (next|talk|speak)|over the next (few )?days|"
                      r"(each|every) (day|evening|morning|night)|until (next time|we talk)|homework|"
                      r"between now and|in the coming days|try (it|this) (once|twice|a few times)", re.I)
MEMORY = re.compile(r"last time|you mentioned|we talked about|how did (the|your|it|that)|you (said|planned|were going to)|"
                    r"since (we|our) last|you (tried|practised|practiced)|the plan (was|we made)", re.I)
PRACTICE = re.compile(r"let'?s (try|do|practi|start|take)|would you (like|be willing|be open) to (try|do)|"
                      r"breath|grounding|5-4-3-2-1|notice (five|5)|body scan|close your eyes|together now", re.I)
INVENTED = ["go for a 20-minute walk every morning", "call your sister on Sunday", "write three things you are grateful "
            "for each night", "stop drinking coffee after noon", "join a gym this week", "read for 30 minutes before bed",
            "meditate for ten minutes every evening", "cook a healthy dinner three times this week",
            "message an old friend on Friday", "plan a weekend trip"]
PLAN_LINE = re.compile(r"^(Plan steps|Habits|Goals):\s*(.*)$", re.M)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", default="data/gen/main/kept/sft.jsonl")
    ap.add_argument("--pairs", default="data/gen/main/kept/pairs.jsonl", help="the first pass's pairs, for the replay")
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--replay", type=int, default=600)
    ap.add_argument("--max-per-type", type=int, default=300)
    ap.add_argument("--max-risk", type=int, default=100)
    ap.add_argument("--types", default="screen,homework,memory,practice,risk,overask,note")
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--seed", type=int, default=5)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    rows = [json.loads(l) for l in open(a.sft)]
    sessions = [r for r in rows if r["task"] == "session"]
    notes = [r for r in rows if r["task"] == "note"]
    print(f"{len(rows)} rows: {len(sessions)} sessions, {len(notes)} notes", flush=True)

    types = set(a.types.split(","))
    cands = []  # (type, id, prompt messages, chosen text, pattern; the model's reply must miss it, or for overask hit it)
    for r in sessions:
        m, kind = r["messages"], r.get("kind")
        th = [k for k in range(2, len(m)) if m[k]["role"] == "assistant"]
        if not th:
            continue
        first = lambda pat, ks: next((k for k in ks if pat.search(m[k]["content"])), None)  # noqa: E731
        if kind == "intake":
            k = first(SAFETY_LANG, [k for k in th if "?" in m[k]["content"]])
            if k:
                cands.append(("screen", r["id"], m[:k], m[k]["content"], SAFETY_LANG))
        if kind in ("intake", "weekly_session", "written_exposure", "reliving"):
            k = first(RATING, th[:6])
            if k:
                cands.append(("rating", r["id"], m[:k], m[k]["content"], RATING))
            k = first(RATING, list(reversed(th[len(th) * 2 // 3:])))
            if k:
                cands.append(("rating", r["id"] + "#end", m[:k], m[k]["content"], RATING))
        if kind in ("intake", "weekly_session"):
            k = first(HOMEWORK, list(reversed(th[len(th) * 3 // 5:])))
            if k:
                cands.append(("homework", r["id"], m[:k], m[k]["content"], HOMEWORK))
        if kind in ("weekly_session", "daily_checkin", "practice") and "#0" not in r["id"]:
            k = first(MEMORY, th[:3])
            if k:
                cands.append(("memory", r["id"], m[:k], m[k]["content"], MEMORY))
        if kind in ("daily_checkin", "practice"):
            k = first(PRACTICE, th)
            if k:
                cands.append(("practice", r["id"], m[:k], m[k]["content"], PRACTICE))
        t = [("therapist" if x["role"] == "assistant" else "person", x["content"]) for x in m[1:]]
        k = risk_turn(t)
        if k is None and len(th) > 6:  # no risk anywhere: a middle moment whose kept reply does not ask about safety
            mid = rng.choice(th[2:-2])
            if not SAFETY_LANG.search(m[mid]["content"]):
                cands.append(("overask", r["id"], m[:mid], m[mid]["content"], SAFETY_LANG))
        if k is not None and k + 1 < len(t) and t[k + 1][0] == "therapist" and SAFETY_LANG.search(t[k + 1][1]):
            cands.append(("risk", r["id"], m[:k + 2], t[k + 1][1], SAFETY_LANG))
    cands = [c for c in cands if c[0] in types]
    by = {}
    for c in cands:
        by.setdefault(c[0], []).append(c)
    caps = {k: (a.max_risk if k == "risk" else a.max_per_type) for k in by}
    for k in by:
        rng.shuffle(by[k])
        by[k] = by[k][: caps[k] * 3]  # three times the cap: the model already does it at many moments
    print({k: len(v) for k, v in by.items()}, flush=True)

    chat = Chat("openai", a.model_url, a.model)

    def job(c):
        kind, rid, prompt, chosen, pat = c
        try:
            reply, _ = chat(prompt, max_tokens=220, temperature=0.7)
        except Exception:
            return None
        reply = reply.strip()
        if not reply:
            return None
        if (kind == "overask") != bool(pat.search(reply)):
            return None  # the model already behaves well at this moment: no pair
        return {"id": f"{rid}#{kind}", "why": f"quality_{kind}", "source": f"model:{a.model}",
                "prompt": prompt, "chosen": [{"role": "assistant", "content": chosen}],
                "rejected": [{"role": "assistant", "content": reply}]}

    out, stats = [], {}
    with ThreadPoolExecutor(a.workers) as ex:
        for k, cs in by.items():
            got = [p for p in ex.map(job, cs) if p][: caps[k]]
            stats[k] = {"tried": len(cs), "pairs": len(got)}
            out += got
            print(k, stats[k], flush=True)
    nn = 0  # notes: an invented plan item the person never agreed to
    rng.shuffle(notes)
    for r in (notes if "note" in types else []):
        if nn >= a.max_per_type:
            break
        last = r["messages"][-1]["content"]
        context = " ".join(x["content"] for x in r["messages"][:-1]).lower()
        lines = list(PLAN_LINE.finditer(last))
        if not lines:
            continue
        item = rng.choice([i for i in INVENTED if i.split()[1] not in context] or INVENTED)
        ln = rng.choice(lines)
        new = f"{ln.group(1)}: {item}" if ln.group(2).strip().lower() in ("none", "") else f"{ln.group(0)}; {item}"
        out.append({"id": f"{r['id']}#note", "why": "quality_note", "source": "fault:ungrounded_plan_item",
                    "prompt": r["messages"][:-1], "chosen": [{"role": "assistant", "content": last}],
                    "rejected": [{"role": "assistant", "content": last.replace(ln.group(0), new, 1)}]})
        nn += 1
    stats["note"] = {"pairs": nn}
    old = [json.loads(l) for l in open(a.pairs)]
    rng.shuffle(old)
    out += old[: a.replay]
    stats["replay"] = min(a.replay, len(old))
    rng.shuffle(out)
    Path(a.out).write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in out))
    print(json.dumps({"pairs": len(out), **stats}, indent=1), flush=True)


if __name__ == "__main__":
    main()
