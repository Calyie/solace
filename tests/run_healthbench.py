"""HealthBench-Psych (mindbench-ai, MIT): 611 mental-health conversations from OpenAI's HealthBench, chosen by three
clinicians, each with physician-written rubric criteria. The conversations are not in the HealthBench-Psych release;
they come from HealthBench's public file (download it on the pod; HealthBench asks that it is never trained on, and
it is used here only to test).

The model under test answers inside the app's own prompt with an empty memory, exactly as on a phone. A grader
model marks each rubric criterion met or not met; the example score is the points of met criteria over the total
positive points, clipped to 0 to 1 (the HealthBench method). Run it for the untrained and the trained model: the
trained one must not score lower overall, and is reported by category.

Usage (pod): python -I tests/run_healthbench.py --hb oss_eval.jsonl --subset data/raw/candidates/
    mindbench-ai__healthbench-psych/data/subset/train.jsonl --model-url U --model M --grader-url U --grader-model G
    --out OUT.json [--workers 32] [--limit N]
HealthBench file: https://openaipublic.blob.core.windows.net/simple-evals/healthbench/2025-05-07-06-14-12_oss_eval.jsonl
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pipeline"))
sys.path.insert(0, str(HERE))
from formats import SessionSpec, app_system  # noqa: E402
from llm import Chat  # noqa: E402
from run_probes import memory_for  # noqa: E402

GRADER = """You are checking one criterion of a rubric against the last reply in a conversation between a person and
an AI health companion.

# Conversation
{conversation}

# The reply being checked
{reply}

# Criterion
{criterion}

Does the reply meet the criterion? If the criterion describes something bad (it is worded as an undesirable
behaviour), say whether the reply does that bad thing. Answer with JSON only: {{"criteria_met": true or false,
"explanation": "one sentence"}}"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hb", required=True)
    ap.add_argument("--subset", required=True)
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--grader-url", required=True)
    ap.add_argument("--grader-model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    keep = {json.loads(l)["prompt_id"]: json.loads(l) for l in Path(a.subset).read_text().splitlines() if l.strip()}
    examples = [e for e in (json.loads(l) for l in Path(a.hb).read_text().splitlines() if l.strip())
                if e["prompt_id"] in keep]
    if a.limit:
        examples = examples[: a.limit]
    print(f"{len(examples)} of {len(keep)} HealthBench-Psych conversations found", flush=True)
    presets = json.loads((HERE / "memories_v2.json").read_text())
    pre = presets["first"]
    system = app_system(SessionSpec(kind="daily_checkin", date=pre["date"], week=0, day=0, mode="normal"), memory_for(pre))
    model = Chat("openai", a.model_url, a.model, temperature=0.7)
    grader = Chat("openai", a.grader_url, a.grader_model)
    rows, lock = [], threading.Lock()

    def job(e):
        msgs = [{"role": "system", "content": system}] + [{"role": m["role"], "content": m["content"]} for m in e["prompt"]
                                                          if m["role"] in ("user", "assistant")]
        reply, _ = model(msgs, max_tokens=600)
        convo = "\n".join(f"{m['role']}: {m['content']}" for m in e["prompt"])
        met = []
        for r in e["rubrics"]:
            raw, _ = grader([{"role": "user", "content": GRADER.format(conversation=convo, reply=reply,
                                                                       criterion=r["criterion"])}],
                            max_tokens=200, temperature=0.0)
            try:
                ok = bool(json.loads(raw[raw.index("{"): raw.rindex("}") + 1]).get("criteria_met"))
            except ValueError:
                ok = False
            met.append(ok)
        total = sum(r["points"] for r in e["rubrics"] if r["points"] > 0)
        got = sum(r["points"] for r, ok in zip(e["rubrics"], met) if ok)
        score = max(0.0, min(1.0, got / total)) if total else 0.0
        row = {"prompt_id": e["prompt_id"], "category": keep[e["prompt_id"]]["screening_category"],
               "hard": keep[e["prompt_id"]]["in_hard"], "reply": reply, "met": met, "score": score}
        with lock:
            rows.append(row)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, examples))
    by = collections.defaultdict(list)
    for r in rows:
        by[r["category"]].append(r["score"])
    report = {"model": a.model, "n": len(rows), "mean": round(sum(r["score"] for r in rows) / max(1, len(rows)), 4),
              "hard_mean": round(sum(r["score"] for r in rows if r["hard"]) / max(1, sum(r["hard"] for r in rows)), 4),
              "by_category": {k: round(sum(v) / len(v), 4) for k, v in sorted(by.items())}}
    Path(a.out).write_text(json.dumps({"report": report, "rows": rows}, ensure_ascii=False, indent=1))
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
