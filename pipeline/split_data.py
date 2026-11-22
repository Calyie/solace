"""Help me start training rows (2026-11-06, MODEL_REVIEW F6): the feature was neither trained nor tested. For kept
training sessions, take a task from the person's own plans in the app's memory (today's plan, a step with no day set,
a goal's next step), have the writer split it (prompts/writer_split.md), and keep the reply only if the app can use it
(formats.split_faults). The row is what the app sends: the session prompt with memory, then the split instruction.

  python -I pipeline/split_data.py --sft data/gen/v3/kept/sft.jsonl --url http://localhost:8000 --model gemma26b \
      --out data/gen/v3/kept/split.jsonl
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
from formats import PROMPTS, split_faults, split_instruction  # noqa: E402
from llm import Chat  # noqa: E402

TASK_LINES = [re.compile(r"^Today's plan: (?!none)(.+)$", re.M), re.compile(r"^This week, no day set: (.+)$", re.M),
              re.compile(r"next step: ([^,;]+)")]


def tasks_in(system: str) -> list[str]:
    plans = system[system.find("Plans kept by the app"):] if "Plans kept by the app" in system else ""
    found = []
    for rx in TASK_LINES:
        for m in rx.finditer(plans):
            for t in re.split(r";\s*", m.group(1)):
                t = re.sub(r"^\d{1,2}:\d{2}\s+", "", re.sub(r"\s*\(.*?\)\s*$", "", t)).strip().rstrip(".")
                if 3 <= len(t.split()) <= 14 and t not in found and t.split()[0].lower() not in ("a", "an", "wait"):
                    found.append(t)
    return found


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max", type=int, default=400)
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--seed", type=int, default=5)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    jobs, seen = [], set()
    for r in map(json.loads, open(a.sft)):
        if r.get("task") != "session":
            continue
        system = r["messages"][0]["content"]
        for t in tasks_in(system):
            if t.lower() not in seen:
                seen.add(t.lower())
                jobs.append((r["id"], system, t))
    rng.shuffle(jobs)
    jobs = jobs[: a.max]
    chat = Chat("openai", a.url, a.model, temperature=0.7)
    guide = (PROMPTS / "writer_split.md").read_text()

    def one(job):
        rid, system, task = job
        memory = system[system.find("WHAT YOU REMEMBER"):] if "WHAT YOU REMEMBER" in system else system
        for _ in range(2):
            reply, _u = chat([{"role": "system", "content": guide},
                              {"role": "user", "content": f"{memory}\n\nThe task: {task}"}], max_tokens=250)
            reply = reply.strip()
            if not split_faults(task, reply):
                return {"id": f"{rid}#split", "task": "split",
                        "messages": [{"role": "system", "content": system},
                                     {"role": "user", "content": split_instruction(task)},
                                     {"role": "assistant", "content": reply}]}
        return None

    with ThreadPoolExecutor(a.workers) as ex:
        rows = [x for x in ex.map(one, jobs) if x]
    Path(a.out).write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in rows))
    print(f"{len(rows)} of {len(jobs)} tasks kept")


if __name__ == "__main__":
    main()
