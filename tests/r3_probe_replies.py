"""Round 3: the model's replies at a spread of the service probes' moments (tests/probes_v4.jsonl), under prompt v5,
for reading and judging in the project's own session (owner, 2026-11-19: "you be the judge"). The probes' own pass
conditions were written for the earlier question-first standard, so they are not applied by a model judge here: each
row carries the moment, the method the probe expects, and the reply.

  APP_PROMPT_VERSION=v5 python -I tests/r3_probe_replies.py --url http://127.0.0.1:8097 --per-service 5 --out x.jsonl
"""
import argparse
import json
import random
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pipeline"))
from formats import SessionSpec, memory_from_dict, training_messages  # noqa: E402


def generate(url: str, messages: list[dict]) -> str:
    body = {"messages": messages, "max_tokens": 1200, "temperature": 0.7, "top_k": 0, "top_p": 1.0, "min_p": 0.0,
            "repeat_penalty": 1.0, "chat_template_kwargs": {"enable_thinking": False}}
    req = Request(f"{url}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    return (json.loads(urlopen(req, timeout=900).read())["choices"][0]["message"]["content"] or "").strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--per-service", type=int, default=5)
    ap.add_argument("--seed", type=int, default=19)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    presets = json.loads((HERE / "memories_v2.json").read_text())
    probes = [json.loads(l) for l in (HERE / "probes_v4.jsonl").read_text().splitlines() if l.strip()]
    by: dict[str, list] = {}
    for p in probes:
        if p.get("service"):
            by.setdefault(p["service"], []).append(p)
    rng = random.Random(a.seed)
    picked = [p for s in sorted(by) for p in rng.sample(by[s], min(a.per_service, len(by[s])))]

    def one(p):
        preset = p.get("memory_preset") or presets[p["preset"]]
        spec = SessionSpec(kind=p["kind"], date=preset["date"], week=0, day=0, mode=p["mode"] or preset["mode"],
                           therapist_name="Maya")
        memory = memory_from_dict(preset["memory"], preset.get("today", ""))
        msgs = training_messages(spec, memory, [tuple(t) for t in p["turns"]])
        try:
            reply = generate(a.url, msgs)
        except Exception as e:
            reply = f"[error: {e!r}]"
        return {"id": p["id"], "service": p["service"], "moment": p.get("moment", ""), "kind": p["kind"],
                "turns": p["turns"][-4:], "expects": p.get("expect", ""), "reply": reply}

    with ThreadPoolExecutor(a.workers) as ex, open(a.out, "w") as f:
        for row in ex.map(one, picked):
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            f.flush()
            print(row["id"], "|", row["reply"][:100].replace("\n", " "), flush=True)


if __name__ == "__main__":
    main()
