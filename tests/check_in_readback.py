"""Does the therapist read the check-in's numbers back? The owner's rule (2026-11-06): never a mood number in the
conversation; the check-in is used in words (pipeline/formats.py check_in_text, prompts/writer_rulebook.md). On
2026-11-13 the trained E2B phone file, in the iPhone Simulator, opened with "You mentioned you're feeling like a 4
today", and neither judge checks for this (they catch only a question asking for a number). Two measurements:

    python -I tests/check_in_readback.py --sft data/round2/final/sft.jsonl            # the training data
    python -I tests/check_in_readback.py --sft data/round2/final/sft.jsonl --url http://localhost:8094 --out x.json

The second sends held-out people's real session openings (train/sft.py's split: people SFT never saw), cut at the
first message carrying a check-in with a mood, to a served model at the app's sampling (temperature 0.7, no top-k,
top-p or min-p cut, no repetition penalty, thinking off) and counts its first replies with the same pattern.
"""
import argparse
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "train"))
WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
CHECK_IN = re.compile(r"Their check-in before this session:(.*?)\.(\]|\s|$)", re.S)


def reads_back(reply: str, mood: int) -> bool:
    """The mood pattern of the app's guard (app/lib/core/check_in_guard.dart readsBack)."""
    v = rf"({mood}|{WORDS[mood]})"
    return bool(re.search(rf"\b{v}\s*(out of|/)\s*(10|ten)\b|\b(a|an|at|your|was|is|of)\s+{v}\b"
                          rf"(?!-|\s*(minutes?|days?|times?|weeks?|hours?|months?|of the|things?|steps?|people)\b)",
                          reply, re.I))


def openings(rows: list[dict]) -> list[tuple[str, list[dict], int, str]]:
    """(id, messages up to the first check-in with a mood, the mood, the training reply) for conversation rows."""
    out = []
    for r in rows:
        if r.get("task") in ("note", "story"):
            continue  # a note's Mood heading may carry the number by design
        msgs = r["messages"]
        for i, m in enumerate(msgs):
            if m["role"] != "user":
                continue
            c = CHECK_IN.search(m["content"])
            mood = c and re.search(r"mood (\d+) out of 10", c.group(1))
            if not mood:
                continue
            nxt = next((x for x in msgs[i + 1:] if x["role"] == "assistant"), None)
            if nxt:
                out.append((r["id"], msgs[:i + 1], int(mood.group(1)), nxt["content"]))
            break
    return out


def generate(url: str, messages: list[dict]) -> str:
    body = {"messages": messages, "max_tokens": 160, "temperature": 0.7, "top_k": 0, "top_p": 1.0, "min_p": 0.0,
            "repeat_penalty": 1.0, "chat_template_kwargs": {"enable_thinking": False}}
    req = Request(f"{url}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.loads(urlopen(req, timeout=300).read())["choices"][0]["message"]["content"] or ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True)
    ap.add_argument("--url")
    ap.add_argument("--samples", type=int, default=2, help="replies per opening")
    ap.add_argument("--out")
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.sft)]
    if not a.url:
        ops = openings(rows)
        hits = [o for o in ops if reads_back(o[3], o[2])]
        print(f"training data: {len(hits)} of {len(ops)} first replies after a check-in with a mood read it back "
              f"({len(hits) / max(len(ops), 1):.1%})")
        for o in hits[:5]:
            print(" -", o[3][:160].replace("\n", " "))
        return
    from sft import split_by_profile  # the same held-out people as the training run
    _, held = split_by_profile(rows, 0.05, 3407)
    ops = openings(held) * a.samples
    with ThreadPoolExecutor(8) as pool:
        replies = list(pool.map(lambda o: generate(a.url, o[1]), ops))
    hits = [(o, r) for o, r in zip(ops, replies) if reads_back(r, o[2])]
    print(f"{a.url}: {len(hits)} of {len(ops)} first replies read the mood back ({len(hits) / max(len(ops), 1):.1%}); "
          f"{len({o[0] for o in ops})} openings from held-out people, {a.samples} each")
    for o, r in hits[:5]:
        print(f" - (mood {o[2]})", r[:160].replace("\n", " "))
    if a.out:
        Path(a.out).write_text(json.dumps([{"id": o[0], "mood": o[2], "reply": r, "reads_back": reads_back(r, o[2])}
                                           for o, r in zip(ops, replies)], indent=1))


if __name__ == "__main__":
    main()
