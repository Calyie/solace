"""Relabel the safety classifier's training messages one message at a time (2026-11-05). MindGuard labels a user turn
by the state of the whole conversation, so "I have a niece. She's 6." is labelled risk inside a risk conversation,
and its first turns are 95 percent safe, which taught the classifier that a message without context is probably
safe (it then scored "I need to talk to someone right now before I do something stupid" at 0.0). The app needs the
message's own meaning, read with the therapist's last words. A judge from a third model family gives two labels per
message: with the therapist's last words, and alone. train/safety_clf.py --relabelled keeps a message only when the
judge agrees with the original label, and adds a copy without context when the message alone shows risk.

  python -I pipeline/safety_relabel.py --out data/gen/main/safety_relabel.jsonl --url http://localhost:8003 \
      --model gptoss20b --extra data/gen/main/safety_extra.jsonl
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "train"))
from llm import Chat  # noqa: E402
from safety_clf import NORMALISE, mindguard  # noqa: E402

LABEL = """You label messages for the safety check of a private therapy app. Each item shows the therapist's last words
(may be empty) and the person's reply. Decide what the person's REPLY shows, twice:
- in_context: the reply read together with the therapist's last words;
- alone: the reply read on its own, with no other words.
Labels:
- self_harm: a CURRENT risk to themselves: suicidal thoughts (direct or hinted), wishing to be dead or not exist,
  feeling others would be better off without them, self-harm now or recently, preparing to die or saying goodbye,
  a recent attempt, or urges to do something dangerous to themselves.
- harm_others: a CURRENT risk to someone else: intent, urges, fantasies or threats of hurting a person, or ongoing
  violence or abuse toward a partner or child.
- safe: anything else, including low mood, self-criticism, loneliness or hopelessness about one area of life
  without thoughts of death or harm; figures of speech; risk that ended long ago; denials; talk about other people's
  deaths, illness or the news; and replies that only continue a conversation without showing risk themselves.
{items}
Answer with JSON only: {{"labels": [{{"in_context": "self_harm" | "harm_others" | "safe", "alone": "..."}}, ...]}}
with one entry per item, in the same order."""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default="http://localhost:8003")
    ap.add_argument("--model", default="gptoss20b")
    ap.add_argument("--data-root", default="data/raw/candidates")
    ap.add_argument("--extra", nargs="*", default=[], help="JSONL rows to relabel too (e.g. safety_extra.jsonl)")
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--no-mindguard", action="store_true", help="relabel only the --extra rows")
    a = ap.parse_args()
    rows = [] if a.no_mindguard else mindguard(Path(a.data_root) / "swordhealth__MindGuard-trainingset" / "train.parquet")
    for r in rows:
        r["source"] = "mindguard"
    for f in a.extra:
        for line in Path(f).read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                rows.append({"context": r.get("context", ""), "text": r["text"], "group": r.get("group", r["text"][:40]),
                             "label": NORMALISE.get(r["label"], r["label"]), "source": Path(f).stem})
    out, lock = Path(a.out), threading.Lock()
    done = {(json.loads(l)["source"], json.loads(l)["group"], json.loads(l)["text"]) for l in out.read_text().splitlines()} \
        if out.exists() else set()
    todo = [r for r in rows if (r["source"], r["group"], r["text"]) not in done]
    batches = [todo[i:i + a.batch] for i in range(0, len(todo), a.batch)]
    chat = Chat("openai", a.url, a.model)
    stats = {"rows": 0, "failed_batches": 0}
    print(f"{len(rows)} rows, {len(todo)} to label, {len(batches)} calls", flush=True)

    def job(batch):
        items = "\n".join(f"{i + 1}. Therapist: {(r['context'] or '(nothing yet)')[-300:]}\n   Reply: {r['text']}"
                          for i, r in enumerate(batch))
        ok = {"self_harm", "harm_others", "safe"}
        for _ in range(2):
            try:
                raw, _ = chat([{"role": "user", "content": LABEL.format(items=items)}], max_tokens=60 * len(batch) + 200,
                              temperature=0.0)
                labs = json.loads(raw[raw.index("{"): raw.rindex("}") + 1])["labels"]
                if len(labs) == len(batch) and all(l.get("in_context") in ok and l.get("alone") in ok for l in labs):
                    break
            except Exception:
                pass
        else:
            with lock:
                stats["failed_batches"] += 1
            return
        with lock:
            stats["rows"] += len(batch)
            with out.open("a") as f:
                f.writelines(json.dumps({**r, "label_ctx": l["in_context"], "label_alone": l["alone"]},
                                        ensure_ascii=False) + "\n" for r, l in zip(batch, labs))
            if stats["rows"] % 800 < len(batch):
                print(stats, flush=True)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, batches))
    lab = [json.loads(l) for l in out.read_text().splitlines()]
    agree = sum(r["label"] == r["label_ctx"] for r in lab)
    print(json.dumps({**stats, "labelled": len(lab), "agree_with_original": agree,
                      "risk_alone": sum(r["label_alone"] != "safe" for r in lab)}, indent=1), flush=True)


if __name__ == "__main__":
    main()
