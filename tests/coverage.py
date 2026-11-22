"""Coverage map of a profile bank (owner, 2026-11-03): source and topic, age band, country, risk, kind of person and
style, so gaps show before generation, and again on the kept data after judging.
Usage: python -I tests/coverage.py data/gen/profiles.jsonl [--kept data/gen/main/kept/sft.jsonl]
"""
import collections
import json
import sys
from pathlib import Path

rows = [json.loads(l) for l in Path(sys.argv[1]).read_text().splitlines() if l.strip()]
kept_ids = None
if "--kept" in sys.argv:
    kept_ids = {json.loads(l)["id"].split("#")[0].rstrip("LR") for l in Path(sys.argv[sys.argv.index("--kept") + 1]).read_text().splitlines() if l.strip()}
    rows = [r for r in rows if r["id"] in kept_ids]


def band(age: int) -> str:
    return "18-24" if age < 25 else "25-34" if age < 35 else "35-49" if age < 50 else "50-64" if age < 65 else "65+"


def kind(src: str) -> str:
    return src.split(":")[0] if not src.startswith("topic:") else "topic"


tables = {
    "source": collections.Counter(kind(r["source"]) for r in rows),
    "topic": collections.Counter(r["source"][6:] for r in rows if r["source"].startswith("topic:")),
    "age band": collections.Counter(band(int(r["age"])) for r in rows),
    "country": collections.Counter(r["country"] for r in rows),
    "risk": collections.Counter(r["risk"].split(";")[0].split(".")[0][:40].lower() for r in rows),
    "gender": collections.Counter(r["gender"].lower() for r in rows),
    "mode": collections.Counter(r.get("mode", "normal") for r in rows),
}
print(f"{len(rows)} profiles" + (" (kept after judging)" if kept_ids is not None else ""))
for name, c in tables.items():
    print(f"\n{name}:")
    for k, v in c.most_common():
        print(f"  {v:5d}  {k}")
thin = [t for t, v in tables["topic"].items() if v < 3]
print("\ntopics with fewer than 3 people:", thin or "none")
