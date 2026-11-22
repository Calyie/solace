"""Second training pass, safety (2026-11-05; owner: a second pass only if the tests need it, within the 48-hour cap).
The tests found one weakness above all: the trained models skip the safety question in about half of all first
sessions (missed_safety_screen: 39 of E4B's 102 failed sessions), never point to crisis support in a crisis turn
(red team: 0 of 27), and leave risk out of the note (safety_not_recorded, 17). This builds preference pairs from the
kept training sessions (training people only; the test people are separate), with the rejected reply written by the
model being trained, at the same moment:
  screen   an intake, at the turn where the kept session asks about safety; kept only if the model does not ask
  risk     the turn right after the person's first risk message (judge.risk_turn); kept only if the model does not
           address safety
  support  the turn after the person answers the safety question, where the kept reply points to crisis support or
           a trusted person; kept only if the model does not
  note     a session with risk: the kept note against the same note with "Safety: no concerns"
plus a random sample of the original pairs, so the rest of what the first pass taught is held in place.

  python -I pipeline/safety_pairs.py --model-url http://localhost:8002 --model e4b-dpo --out data/gen/main/kept/safety_pairs_e4b.jsonl
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

SUPPORT = re.compile(r"crisis|helpline|hotline|emergency|support (page|line|button|number)|the app shows|"
                     r"someone (you trust|close|nearby)|reach out to|call (someone|a friend|them)|"
                     r"(friend|family member|partner|someone) (who )?(can|could) (be|stay) with you", re.I)
SAFETY_LINE = re.compile(r"^Safety:.*$", re.M)


def turns_of(msgs: list[dict]) -> list[tuple[str, str]]:
    return [("therapist" if m["role"] == "assistant" else "person", m["content"]) for m in msgs[1:]]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", default="data/gen/main/kept/sft.jsonl")
    ap.add_argument("--pairs", default="data/gen/main/kept/pairs.jsonl", help="the first pass's pairs, for the replay")
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--replay", type=int, default=500)
    ap.add_argument("--max-per-type", type=int, default=450)
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--seed", type=int, default=5)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    rows = [json.loads(l) for l in open(a.sft)]
    sessions = [r for r in rows if r["task"] == "session"]
    notes = [r for r in rows if r["task"] == "note"]
    print(f"{len(rows)} rows: {len(sessions)} sessions, {len(notes)} others", flush=True)

    cands = []  # (type, id, prompt messages, chosen text, test applied to the model's reply)
    for r in sessions:
        m = r["messages"]
        if r.get("kind") == "intake":
            i = next((k for k in range(2, len(m)) if m[k]["role"] == "assistant" and "?" in m[k]["content"]
                      and SAFETY_LANG.search(m[k]["content"])), None)
            if i:
                cands.append(("screen", r["id"], m[:i], m[i]["content"], SAFETY_LANG))
        t = turns_of(m)
        k = risk_turn(t)
        if k is not None and k + 1 < len(t) and t[k + 1][0] == "therapist" and SAFETY_LANG.search(t[k + 1][1]):
            cands.append(("risk", r["id"], m[:k + 2], t[k + 1][1], SAFETY_LANG))
            # the person's answer to the safety question, then the kept reply that points to support
            j = next((x for x in range(k + 2, min(k + 8, len(t))) if t[x][0] == "therapist" and SUPPORT.search(t[x][1])), None)
            if j is not None:
                cands.append(("support", r["id"], m[:j + 1], t[j][1], SUPPORT))
    by = {}
    for c in cands:
        by.setdefault(c[0], []).append(c)
    for k in by:
        rng.shuffle(by[k])
        by[k] = by[k][: a.max_per_type * 2]  # twice the cap: some will not need a pair
    print({k: len(v) for k, v in by.items()}, flush=True)

    chat = Chat("openai", a.model_url, a.model)

    def job(c):
        kind, rid, prompt, chosen, test = c
        try:
            reply, _ = chat(prompt, max_tokens=220, temperature=0.7)
        except Exception as e:
            return None
        reply = reply.strip()
        if not reply or test.search(reply):
            return None  # the model already does it here: no pair
        return {"id": f"{rid}#{kind}", "why": f"safety_{kind}", "source": f"model:{a.model}",
                "prompt": prompt, "chosen": [{"role": "assistant", "content": chosen}],
                "rejected": [{"role": "assistant", "content": reply}]}

    out = []
    stats = {}
    with ThreadPoolExecutor(a.workers) as ex:
        for k, cs in by.items():
            got = [p for p in ex.map(job, cs) if p][: a.max_per_type]
            stats[k] = {"tried": len(cs), "pairs": len(got)}
            out += got
    # notes: a session with risk whose kept note records it, against the same note saying "no concerns"
    nn = 0
    for r in notes:
        last = r["messages"][-1]["content"]
        mm = SAFETY_LINE.search(last)
        if mm and not re.search(r"no (safety )?concerns?|none", mm.group(0), re.I) and nn < a.max_per_type:
            out.append({"id": f"{r['id']}#note", "why": "safety_note", "source": "fault:safety_not_recorded",
                        "prompt": r["messages"][:-1], "chosen": [{"role": "assistant", "content": last}],
                        "rejected": [{"role": "assistant", "content": SAFETY_LINE.sub("Safety: no concerns", last, 1)}]})
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
