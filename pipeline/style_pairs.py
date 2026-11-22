"""Second training pass, the human and experienced therapist (owner, 2026-11-05: always warm, kind, empathetic and
very human in how they listen and talk, never a scripted AI character; more experienced; research-backed methods
that fit the situation). At random moments in the kept training sessions (training people only) the model being
trained writes two replies; a supervisor judge (prompts/judge_pair_style.md) compares them twice, in both orders, and
a pair is kept only when both verdicts agree. The model learns to do more of its own best replies, which generalises
better than copying a pattern.

  python -I pipeline/style_pairs.py --model-url http://localhost:8002 --model e4b-dpo --judge-url http://localhost:8000 \
      --judge-model gemma26b --out data/gen/main/kept/style_pairs_e4b.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
import judge  # noqa: E402
from llm import Chat  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", default="data/gen/main/kept/sft.jsonl")
    ap.add_argument("--model-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--judge-url", required=True)
    ap.add_argument("--judge-model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--moments", type=int, default=700)
    ap.add_argument("--cap", type=int, default=300)
    ap.add_argument("--workers", type=int, default=48)
    ap.add_argument("--seed", type=int, default=9)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    sessions = [r for r in map(json.loads, open(a.sft)) if r["task"] == "session"]
    moments = []
    for r in rng.sample(sessions, min(a.moments, len(sessions))):
        th = [k for k in range(2, len(r["messages"])) if r["messages"][k]["role"] == "assistant"]
        if len(th) > 3:
            moments.append((r["id"], r["messages"][: rng.choice(th[1:-1])]))
    model = Chat("openai", a.model_url, a.model)
    jud = Chat("openai", a.judge_url, a.judge_model)
    rubric = (ROOT / "prompts" / "judge_pair_style.md").read_text()

    def prefer(ctx, first, second):
        convo = "\n".join(f"{'Therapist' if m['role'] == 'assistant' else 'Person'}: {m['content']}" for m in ctx[1:])
        ask = (f"# What the therapist remembers\n{judge.memory_from_system(ctx[0]['content'])}\n\n# Conversation\n"
               f"{convo}\n\n# Reply A\n{first}\n\n# Reply B\n{second}")
        raw, _ = jud([{"role": "system", "content": rubric}, {"role": "user", "content": ask}], max_tokens=120,
                     temperature=0.0)
        try:
            return json.loads(raw[raw.index("{"): raw.rindex("}") + 1]).get("better", "tie")
        except ValueError:
            return "tie"

    def job(mo):
        rid, ctx = mo
        try:
            x, _ = model(ctx, max_tokens=220, temperature=1.0)
            y, _ = model(ctx, max_tokens=220, temperature=1.0)
            x, y = x.strip(), y.strip()
            if not x or not y or x == y:
                return None
            v1, v2 = prefer(ctx, x, y), prefer(ctx, y, x)
        except Exception:
            return None
        if v1 == "A" and v2 == "B":
            good, bad = x, y
        elif v1 == "B" and v2 == "A":
            good, bad = y, x
        else:
            return None  # a tie or an order-dependent verdict: no pair
        return {"id": f"{rid}#style@{len(ctx)}", "why": "style", "source": f"model:{a.model}+judge:{a.judge_model}",
                "prompt": ctx, "chosen": [{"role": "assistant", "content": good}],
                "rejected": [{"role": "assistant", "content": bad}]}

    with ThreadPoolExecutor(a.workers) as ex:
        pairs = [p for p in ex.map(job, moments) if p][: a.cap]
    Path(a.out).write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in pairs))
    print(json.dumps({"moments": len(moments), "pairs": len(pairs)}), flush=True)


if __name__ == "__main__":
    main()
