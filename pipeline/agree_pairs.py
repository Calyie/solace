"""Too agreeable, too many questions (owner, 2026-11-05: "We definitely need to improve this issue: AI therapists are
too agreeable and ask too many questions"; the research's two top findings, docs/RESEARCH_THERAPIST_QUALITIES.md).
On-policy pairs from the kept training sessions (training people only), the rejected reply written by the model
being trained at the same moment:
  questions  the kept reply reflects without a question (or asks one) and the model asks one (or two or more)
  agree      after the person states a harsh conclusion about themselves or a plan that may backfire, the kept reply
             and the model's reply are compared twice, in both orders, by a supervisor judge
             (prompts/judge_pair_agree.md); kept only when the kept reply wins both times

  python -I pipeline/agree_pairs.py --model-url http://localhost:8002 --model e4b-dpo --judge-url http://localhost:8000 \
      --judge-model gemma26b --out data/gen/main/kept/agree_pairs_e4b.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
import judge  # noqa: E402
from llm import Chat  # noqa: E402

DISTORT = re.compile(r"\b(everyone|everybody|nobody|no one) (hates|thinks|cares|likes|wants|notices)|"
                     r"\bI (always|never) (get|do|mess|ruin|fail|say)|"
                     r"\bI'?m (so |such a |just |a |an )?(stupid|useless|worthless|failure|pathetic|burden|hopeless|"
                     r"loser|idiot|unlovable|broken|disappointment|terrible|awful|weak)\b|"
                     r"it'?s (all )?my fault|\bI deserve|\bI'?m going to (quit|tell|send|text|call|confront|stop|drop|"
                     r"cancel|block)|(he|she|they) (was|were|is|are) right (that|about)|what'?s the point|"
                     r"can'?t do anything right|there'?s no point", re.I)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", default="data/gen/main/kept/sft.jsonl")
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--judge-url", required=True)
    ap.add_argument("--judge-model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cap", type=int, default=250)
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--seed", type=int, default=13)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    sessions = [r for r in map(json.loads, open(a.sft)) if r["task"] == "session"]
    rng.shuffle(sessions)
    qs, ag = [], []
    for r in sessions:
        m = r["messages"]
        th = [k for k in range(3, len(m) - 1) if m[k]["role"] == "assistant"]
        if len(th) > 3 and len(qs) < a.cap * 4:
            k = rng.choice(th[1:-1])
            if m[k]["content"].count("?") <= 1:
                qs.append((r["id"], m[:k], m[k]["content"]))
        for k in range(2, len(m) - 1):
            if m[k]["role"] == "user" and DISTORT.search(m[k]["content"]) and m[k + 1]["role"] == "assistant":
                ag.append((r["id"], m[:k + 1], m[k + 1]["content"]))
                break
    rng.shuffle(ag)
    ag = ag[: a.cap * 3]
    print(f"moments: questions {len(qs)}, agree {len(ag)}", flush=True)
    model = Chat("openai", a.model_url, a.model)
    jud = Chat("openai", a.judge_url, a.judge_model)
    rubric = (ROOT / "prompts" / "judge_pair_agree.md").read_text()

    def prefer(ctx, first, second):
        convo = "\n".join(f"{'Therapist' if x['role'] == 'assistant' else 'Person'}: {x['content']}" for x in ctx[1:])
        ask = (f"# What the therapist remembers\n{judge.memory_from_system(ctx[0]['content'])}\n\n# Conversation\n"
               f"{convo}\n\n# Reply A\n{first}\n\n# Reply B\n{second}")
        raw, _ = jud([{"role": "system", "content": rubric}, {"role": "user", "content": ask}], max_tokens=120,
                     temperature=0.0)
        try:
            return json.loads(raw[raw.index("{"): raw.rindex("}") + 1]).get("better", "tie")
        except ValueError:
            return "tie"

    def row(kind, rid, ctx, good, bad):
        return {"id": f"{rid}#{kind}@{len(ctx)}", "why": f"agree_{kind}", "source": f"model:{a.model}",
                "prompt": ctx, "chosen": [{"role": "assistant", "content": good}],
                "rejected": [{"role": "assistant", "content": bad}]}

    def q_job(mo):
        rid, ctx, kept = mo
        try:
            reply = model(ctx, max_tokens=220, temperature=0.7)[0].strip()
        except Exception:
            return None
        k, r_ = kept.count("?"), reply.count("?")
        return row("questions", rid, ctx, kept, reply) if reply and ((k == 0 and r_ >= 1) or (k == 1 and r_ >= 2)) else None

    def a_job(mo):
        rid, ctx, kept = mo
        try:
            reply = model(ctx, max_tokens=220, temperature=0.7)[0].strip()
            if not reply or reply == kept:
                return None
            v1, v2 = prefer(ctx, kept, reply), prefer(ctx, reply, kept)
        except Exception:
            return None
        return row("agree", rid, ctx, kept, reply) if (v1, v2) == ("A", "B") else None

    with ThreadPoolExecutor(a.workers) as ex:
        qp = [p for p in ex.map(q_job, qs) if p][: a.cap]
        apairs = [p for p in ex.map(a_job, ag) if p][: a.cap]
    Path(a.out).write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in qp + apairs))
    print(json.dumps({"questions": len(qp), "agree": len(apairs)}), flush=True)


if __name__ == "__main__":
    main()
