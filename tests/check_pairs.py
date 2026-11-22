"""Preference pairs render as train/dpo.py renders them (readiness check R7, 2026-11-07), with Gemma 4's real
tokenizer and chat template (public files only, no model): every prompt ends at the model turn with thinking off,
and chosen and rejected differ. Run on any pairs file, including the spoken-edit pairs of pipeline/batch.py combine.

  ai-ml-engineering/.venv/bin/python -I tests/check_pairs.py TEMPLATE_DIR PAIRS.jsonl [...]
"""
import collections
import json
import sys
from pathlib import Path

from transformers import AutoTokenizer

tok = AutoTokenizer.from_pretrained(sys.argv[1])
for f in sys.argv[2:]:
    rows = [json.loads(l) for l in Path(f).read_text().splitlines() if l.strip()]
    for r in rows:
        prompt = tok.apply_chat_template(r["prompt"], tokenize=False, add_generation_prompt=True, enable_thinking=False)
        assert "<|think|>" not in prompt and prompt.endswith("<|turn>model\n"), (r["id"], prompt[-80:])
        assert r["chosen"][0]["content"].strip() != r["rejected"][0]["content"].strip(), r["id"]
    print(f"{f}: {len(rows)} pairs render as dpo.py needs;", dict(collections.Counter(r["source"] for r in rows)))
