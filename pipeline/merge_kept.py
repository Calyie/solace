"""Round 2 (2026-11-11): one training set from every folder's kept files (pipeline/batch.py combine), for the training
session to download in one piece. Concatenates kept/sft.jsonl (sessions, notes, story updates, thinking rows) and
kept/pairs_spoken.jsonl, adds the Help me start rows (split.jsonl, A10), and reports the counts by task and the kept
sessions per service against the R5 target, so the data check reads one report.

  python -I pipeline/merge_kept.py --dirs DIR [DIR ...] --split FILE --profiles FILE [FILE ...] --out DIR
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import services  # noqa: E402

TARGET = 100  # kept sessions per service (TASKLIST R5)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dirs", nargs="+", required=True, help="folders holding kept/ (batch.py combine output)")
    ap.add_argument("--split", nargs="*", default=[], help="Help me start rows (pipeline/split_data.py output)")
    ap.add_argument("--profiles", nargs="+", required=True, help="the people, to count sessions per service")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    people = {}
    for f in a.profiles:
        for line in Path(f).read_text().splitlines():
            if line.strip():
                p = json.loads(line)
                people[p["id"]] = p
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    tasks, per_service, seen, by_dir = collections.Counter(), collections.Counter(), set(), {}
    with (out / "sft.jsonl").open("w") as sft, (out / "pairs_spoken.jsonl").open("w") as pairs:
        for d in a.dirs:
            n = 0
            for line in (Path(d) / "kept" / "sft.jsonl").read_text().splitlines():
                if not line.strip():
                    continue
                r = json.loads(line)
                key = (r.get("task"), r["id"])
                if key in seen:  # the same row from two folders would weigh twice
                    continue
                seen.add(key)
                sft.write(line + "\n")
                tasks[r.get("task")] += 1
                n += 1
                if r.get("task") == "session":
                    for s in services.primary(people.get(r["id"].split("#")[0].rstrip("LR"), {})):
                        per_service[s] += 1
            by_dir[d] = n
            f = Path(d) / "kept" / "pairs_spoken.jsonl"
            if f.exists():
                for line in f.read_text().splitlines():
                    if line.strip():
                        pairs.write(line + "\n")
                        tasks["pair_spoken"] += 1
        for f in a.split:
            for line in Path(f).read_text().splitlines():
                if line.strip():
                    sft.write(line + "\n")
                    tasks["split"] += 1
    short = {s.id: per_service[s.id] for s in services.SERVICES if per_service[s.id] < TARGET}
    report = {"rows_by_task": dict(tasks), "rows_by_folder": by_dir,
              "kept_sessions_per_service": dict(per_service.most_common()),
              "services_under_target": short, "target": TARGET}
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=1))
    print(json.dumps({k: report[k] for k in ("rows_by_task", "services_under_target")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
