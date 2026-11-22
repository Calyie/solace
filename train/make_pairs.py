"""Build preference pairs for the second training stage from the kept sessions.

For a few important therapist turns in each kept session (the reply after a risk signal first, then technique and
rating turns, then others) the chosen reply is the judged-good turn, and the rejected reply is either
  - base:  what the untrained model says at the same moment, kept only if the pairwise judge prefers the chosen
           reply in both orders (judges favour whichever reply they see first; asking twice cancels that out), or
  - fault: the same moment answered with one specific fault (flattery, deferring, a tip list, reassurance, or
           carrying on past a risk signal).

Also, with --annomi: real low-quality therapist turns from AnnoMI (23 motivational interviewing demonstrations that
experts rated low quality: lecturing, persuading, confronting) as rejected replies. The chosen reply for the same
moment is written by the writer model under the rulebook, and the pair is kept only if the judge prefers it in both
orders. The conversations are about drinking, smoking and health habits, so the app prompt is a first session with
nothing remembered.

Usage (on the pod, vLLM serving the base model on one port and a judge on another):
  python -I train/make_pairs.py --sft data/gen/main/kept/sft.jsonl --out data/gen/main/kept/pairs.jsonl \
      --base-url http://localhost:8002 --base-model e4b-base --judge-url http://localhost:8000 --judge-model qwen27b
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
from llm import Chat  # noqa: E402
import judge  # noqa: E402

RATING = re.compile(r"\b(0|zero) (to|and) (10|100)\b|out of (10|100)|scale", re.I)
REASSURANCE_ASK = re.compile(r"are you sure|just tell me|promise me|is it (okay|ok|normal)|say (it|that)", re.I)

FAULTS = {
    "flattery": lambda ctx: "You're doing amazingly, honestly. Anyone would feel that way, and you're handling it all "
                            "perfectly. I'm really proud of you.",
    "deferral": lambda ctx: "That sounds like a lot to carry. Let's leave it there for now, and next time we can look at "
                            "some strategies for it.",
    "advice_list": lambda ctx: "Here are some things that can help: try journaling in the evening, go for a walk, get "
                               "more sleep, talk to a friend, and maybe try a meditation app.",
    "reassurance": lambda ctx: "Don't worry, I'm sure everything is fine and nobody is upset with you.",
    "ignore_risk": lambda ctx: "Okay. Let's get back to what we were working on. What happened next?",
}


def pick_turns(msgs: list[dict], k: int, rng: random.Random) -> list[tuple[int, str]]:
    """(index of an assistant turn, why) for up to k important turns; never the opening turn."""
    picks: list[tuple[int, str]] = []
    cands = [i for i, m in enumerate(msgs) if m["role"] == "assistant" and i >= 4]
    for i in cands:
        if judge.RISK.search(msgs[i - 1]["content"]):
            picks.append((i, "risk"))
    for i in cands:
        if len(picks) < k and RATING.search(msgs[i]["content"]) and all(i != p for p, _ in picks):
            picks.append((i, "work"))
    rest = [i for i in cands if all(i != p for p, _ in picks)]
    rng.shuffle(rest)
    picks += [(i, "other") for i in rest[: max(0, k - len(picks))]]
    return picks[:k]


def fault_for(ctx: list[dict], why: str, rng: random.Random) -> str:
    if why == "risk":
        return "ignore_risk"
    if REASSURANCE_ASK.search(ctx[-1]["content"]):
        return "reassurance"
    return rng.choice(["flattery", "deferral", "advice_list"])


def prefer(chat: Chat, ctx: list[dict], first: str, second: str) -> str:
    convo = "\n".join(f"{'Therapist' if m['role'] == 'assistant' else 'Person'}: {m['content']}"
                      for m in ctx[1:])  # the app prompt is not needed to compare replies; the memory is
    mem = judge.memory_from_system(ctx[0]["content"])
    ask = f"# What the therapist remembers\n{mem}\n\n# Conversation\n{convo}\n\n# Reply A\n{first}\n\n# Reply B\n{second}"
    raw, _ = chat([{"role": "system", "content": (ROOT / "prompts" / "judge_pair.md").read_text()},
                   {"role": "user", "content": ask}], max_tokens=120, temperature=0.0)
    try:
        return json.loads(raw[raw.index("{"): raw.rindex("}") + 1]).get("better", "tie")
    except ValueError:
        return "tie"


def annomi_moments(path: Path, rng: random.Random, per_transcript: int = 5) -> list[tuple[str, list[tuple[str, str]], str]]:
    """(transcript id, conversation before the moment as (who, text), the low-quality therapist turn) for turns where
    the therapist gives input (advice, persuasion, information) at length, the typical fault in these transcripts."""
    import csv
    rows = list(csv.DictReader(path.open()))
    by: dict[str, list[dict]] = {}
    for r in rows:
        if r["mi_quality"] == "low":
            by.setdefault(r["transcript_id"], []).append(r)
    out = []
    for tid, rs in sorted(by.items()):
        rs.sort(key=lambda r: int(r["utterance_id"]))
        turns = [("therapist" if r["interlocutor"] == "therapist" else "person", r["utterance_text"].strip()) for r in rs]
        cands = [i for i, r in enumerate(rs) if r["interlocutor"] == "therapist" and i >= 3
                 and r["main_therapist_behaviour"] == "therapist_input" and len(r["utterance_text"].split()) >= 15]
        rng.shuffle(cands)
        for i in sorted(cands[:per_transcript]):
            out.append((tid, turns[max(0, i - 12):i], turns[i][1]))
    return out


def annomi_pairs(a, write, counts) -> None:
    from formats import SessionSpec, Memory, Story, app_system, open_event
    writer = Chat("openai", a.writer_url, a.writer_model, temperature=0.7)
    jud = Chat("openai", a.judge_url, a.judge_model)
    rulebook = (ROOT / "prompts" / "writer_rulebook.md").read_text()
    system = app_system(SessionSpec(kind="intake", date="Monday 2 November", week=1, day=1), Memory(story=Story()))
    moments = annomi_moments(Path(a.annomi), random.Random(a.seed))

    def job(m):
        tid, before, bad = m
        ctx = [{"role": "system", "content": system}, {"role": "user", "content": open_event()}]
        for who, text in before:  # real transcripts have runs by one speaker; the chat format needs turns to alternate
            role = "assistant" if who == "therapist" else "user"
            if ctx[-1]["role"] == role:
                ctx[-1] = {"role": role, "content": ctx[-1]["content"] + " " + text}
            else:
                ctx.append({"role": role, "content": text})
        if ctx[-1]["role"] != "user":  # the bad turn must answer the person
            return
        ask = (rulebook + "\n\n# Task\nWrite only the therapist's next turn in this conversation: one to four "
               "sentences, in the spirit of motivational interviewing (reflect, ask one open question, draw out "
               "their own reasons; no lecturing or persuading).")
        good, _ = writer([{"role": "system", "content": ask}] + ctx[1:], max_tokens=200)
        good = good.strip()
        if prefer(jud, ctx, good, bad) == "A" and prefer(jud, ctx, bad, good) == "B":
            write({"id": f"annomi:{tid}@{len(ctx)}", "why": "annomi_low_quality", "source": "annomi", "prompt": ctx,
                   "chosen": [{"role": "assistant", "content": good}], "rejected": [{"role": "assistant", "content": bad}]})
            counts["annomi_kept"] += 1
        else:
            counts["annomi_dropped"] += 1

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, moments))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--base-model", required=True)
    ap.add_argument("--judge-url", required=True)
    ap.add_argument("--judge-model", required=True)
    ap.add_argument("--per-session", type=int, default=3)
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--max-sessions", type=int, default=0, help="use a random sample of this many kept sessions")
    ap.add_argument("--annomi", help="AnnoMI-full.csv: add pairs with real low-quality turns as the rejected reply")
    ap.add_argument("--writer-url", help="for --annomi: the writer model that writes the chosen reply")
    ap.add_argument("--writer-model")
    a = ap.parse_args()

    sessions = [json.loads(l) for l in Path(a.sft).read_text().splitlines() if l.strip()]
    sessions = [s for s in sessions if s["task"] == "session"]
    if a.max_sessions and len(sessions) > a.max_sessions:
        sessions = random.Random(a.seed).sample(sessions, a.max_sessions)
    base = Chat("openai", a.base_url, a.base_model, temperature=0.7)
    jud = Chat("openai", a.judge_url, a.judge_model)
    lock, counts = threading.Lock(), {"base_kept": 0, "base_dropped": 0, "fault": 0, "annomi_kept": 0,
                                      "annomi_dropped": 0}
    out = open(a.out, "w")

    def write(row):
        with lock:
            out.write(json.dumps(row, ensure_ascii=False) + "\n")

    def job(s):
        rng = random.Random(f"{a.seed}:{s['id']}")
        for i, why in pick_turns(s["messages"], a.per_session, rng):
            ctx, good = s["messages"][:i], s["messages"][i]["content"]
            row = {"id": f"{s['id']}@{i}", "why": why, "prompt": ctx, "chosen": [{"role": "assistant", "content": good}]}
            reply, _ = base(ctx, max_tokens=220)
            if prefer(jud, ctx, good, reply) == "A" and prefer(jud, ctx, reply, good) == "B":
                write({**row, "source": "base", "rejected": [{"role": "assistant", "content": reply}]})
                with lock:
                    counts["base_kept"] += 1
            else:
                with lock:
                    counts["base_dropped"] += 1
            f = fault_for(ctx, why, rng)
            write({**row, "source": f"fault:{f}", "rejected": [{"role": "assistant", "content": FAULTS[f](ctx)}]})
            with lock:
                counts["fault"] += 1

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, sessions))
    if a.annomi:
        annomi_pairs(a, write, counts)
    out.close()
    print(json.dumps(counts))


if __name__ == "__main__":
    main()
