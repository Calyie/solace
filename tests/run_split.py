"""Help me start (2026-11-06, MODEL_REVIEW F6): the model splits a task the person is avoiding into small steps.
The app sends the session prompt with memory, then prompts/app_split_v1.txt with the task, and reads the reply with
parse_split, so a reply the parser cannot read is a broken feature, not a style issue. Checked by code only:

- every non-empty line is a step in the app's format ("1. <step> | <minutes> min"), and there are three to six;
- the first step takes three minutes or less (the prompt asks for about two);
- the steps use at least one word of the task (the prompt asks for their own words).
(formats.split_faults, shared with the data generator pipeline/split_data.py.)

Hand-written tasks for the test people of tests/memories_v2.json; never shown to the writer or used for training.

  python -I tests/run_split.py --model-url URL --model NAME --out OUT.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pipeline"))
from formats import SessionSpec, parse_split, split_faults, split_instruction, training_messages  # noqa: E402
from llm import Chat  # noqa: E402
from run_probes import memory_for  # noqa: E402

TASKS = [
    ("amira_w2", "the Lavoie details"), ("amira_w2", "reply to Daniel's email about the Rousseau drawings"),
    ("amira_w2", "sketch something just for fun"), ("amira_w2", "tidy the flat before Leila visits"),
    ("amira_w2", "book the vet for Pistache"),
    ("meiling_w2", "the quarterly report for the auditors"), ("meiling_w2", "book a GP appointment about the headaches"),
    ("meiling_w2", "reply to my aunt"), ("meiling_w2", "sort out the tax forms"),
    ("meiling_w2", "plan Wei's birthday dinner"),
    ("somchai_w4", "phone the temple school"), ("somchai_w4", "cook rice soup"),
    ("somchai_w4", "sort through Malee's wardrobe"), ("somchai_w4", "prepare a short Thai lesson"),
    ("somchai_w4", "fix the dripping tap"),
    ("julien_w3", "call Karim back"), ("julien_w3", "fill in the sick leave forms"),
    ("julien_w3", "write to the insurance about the crash"), ("julien_w3", "plan a Saturday walk with Hugo"),
    ("julien_w3", "clear the garage"),
    ("first", "start my essay"), ("first", "apply for three jobs"), ("first", "clean my room"),
    ("first", "call my landlord about the boiler"), ("first", "check my bank balance"), ("first", "write my CV"),
    ("first", "pay the electricity bill"), ("first", "email my professor for an extension"),
    ("first", "go to the gym for the first time"), ("first", "start learning Spanish"),
]
def check(task: str, reply: str) -> dict:
    faults = split_faults(task, reply)
    return {"steps": parse_split(reply), "faults": faults, "pass": not faults}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-backend", default="openai")
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    presets = json.loads((HERE / "memories_v2.json").read_text())
    model = Chat(a.model_backend, a.model_url, a.model, temperature=0.7)
    rows = []
    for preset, task in TASKS:
        p = presets[preset]
        spec = SessionSpec(kind="daily_checkin", date=p["date"], week=0, day=0, mode=p["mode"])
        system = training_messages(spec, memory_for(p), [])[0]
        reply, usage = model([system, {"role": "user", "content": split_instruction(task)}], max_tokens=200)
        rows.append({"preset": preset, "task": task, "reply": reply, **check(task, reply), "usage": usage})
        Path(a.out).write_text(json.dumps({"model": a.model, "rows": rows}, ensure_ascii=False, indent=1))
        print(f"{task}: {'PASS' if rows[-1]['pass'] else 'fail ' + ', '.join(rows[-1]['faults'])}", flush=True)
    print(f"total {sum(r['pass'] for r in rows)}/{len(rows)}")


if __name__ == "__main__":
    main()
