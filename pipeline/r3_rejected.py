"""Round 3 (2026-11-19): the shipped model's own reply at each context, as the "rejected" side of a preference pair.

The shipped phone file runs in llama.cpp's llama-server at build b11669, the same engine as the app, with thinking off
and the app's sampling (temperature 0.7), so the rejected replies are what people actually get today.

  python -I r3_rejected.py --contexts contexts.jsonl --url http://127.0.0.1:8090 --name e4b --out pairs_e4b.jsonl
"""
from __future__ import annotations

import argparse
import json
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def reply(url: str, prompt: list[dict]) -> str:
    body = {"messages": prompt, "temperature": 0.7, "top_k": 0, "top_p": 1.0, "min_p": 0.0, "max_tokens": 1200,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)["choices"][0]["message"]["content"].strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--contexts", required=True)
    ap.add_argument("--url", default="http://127.0.0.1:8090")
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    rows = [json.loads(l) for l in Path(a.contexts).read_text().splitlines() if l.strip()]
    done = set()
    if Path(a.out).exists():
        done = {json.loads(l)["id"] for l in Path(a.out).read_text().splitlines() if l.strip()}
    todo = [r for r in rows if r["id"] not in done]
    lock = threading.Lock()
    f = open(a.out, "a")
    n = [0]

    def job(r):
        try:
            bad = reply(a.url, r["prompt"])
        except Exception as e:  # one failure never stops the run
            print("failed", r["id"], repr(e)[:200], flush=True)
            return
        if not bad or bad.strip() == r["chosen"][0]["content"].strip():
            return
        with lock:
            f.write(json.dumps({**r, "source": f"model:{a.name}", "why": "own_reply",
                                "rejected": [{"role": "assistant", "content": bad}]}, ensure_ascii=False) + "\n")
            f.flush()
            n[0] += 1
            if n[0] % 50 == 0:
                print(f"{n[0]} of {len(todo)}", flush=True)

    with ThreadPoolExecutor(a.workers) as pool:
        list(pool.map(job, todo))
    f.close()
    print(f"done: {n[0]} new pairs for {a.name}", flush=True)


if __name__ == "__main__":
    main()
