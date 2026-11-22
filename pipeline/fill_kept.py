"""Round 2 (2026-11-13): the training set when the second judge is much stricter than the first. On session 1's sample
gpt-oss kept 6 of the 32 sessions gemma26b passed (19 percent, A6's bar 40), failing them almost always on work_done
(22 of 26), mostly in daily check-ins; DeepSeek had failed the same way (22 percent). Kept as both judges agree, every
service would fall far short of R5's 100 sessions. So, per folder:
  - the core is what both judges pass (batch.py combine --judges gemma26b,gptoss, moved to kept_both/): sessions, their
    thinking rows, notes and story updates, the spoken-edit pairs
  - a service under 100 core sessions is filled with sessions the first judge passed (batch.py combine --judges
    gemma26b, moved to kept_first/), best first by gpt-oss's own item scores, never one gpt-oss gave a hard fail
    (unsafe, harsh, flattery, invented), until it reaches 100 or the pool runs out; a filled session brings its thinking
    rows and spoken-edit pairs, not its note or story update (those keep both judges)
The result is written to each folder's kept/, which pipeline/merge_kept.py reads as before; fill_report.json says how
many sessions each service has from the core and from the fill.

  python -I pipeline/fill_kept.py --dirs DIR [DIR ...] --profiles FILE [FILE ...] --report FILE
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import judge  # noqa: E402
import services  # noqa: E402

TARGET = 100  # kept sessions per service (TASKLIST R5), as in merge_kept.py
FILL_TASKS = {"session", "think"}  # what a filled session brings; notes and story updates keep both judges


def rows(f: Path) -> list[dict]:
    return [json.loads(l) for l in f.read_text().splitlines() if l.strip()] if f.exists() else []


def session_of(row_id: str) -> str:
    """'g00010#0:think6', 'g00010#0:note' and the pair 'g00010#0@4' all belong to session 'g00010#0'."""
    return row_id.split(":")[0].split("@")[0]


def person_of(key: str) -> str:
    return key.split("#")[0].rstrip("LR")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dirs", nargs="+", required=True)
    ap.add_argument("--profiles", nargs="+", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--second", default="gptoss", help="the stricter judge whose scores rank the fill")
    a = ap.parse_args()
    people = {p["id"]: p for f in a.profiles for p in rows(Path(f))}
    core, seen = collections.Counter(), set()
    for d in map(Path, a.dirs):
        for r in rows(d / "kept_both" / "sft.jsonl"):
            if r.get("task") == "session" and r["id"] not in seen:
                seen.add(r["id"])
                for s in services.primary(people.get(person_of(r["id"]), {})):
                    core[s] += 1
    n_core = len(seen)
    # the pool: sessions the first judge kept and both judges did not, ranked by the second judge's item scores
    pool = []
    for d in map(Path, a.dirs):
        second = {v["key"]: v for v in rows(d / "verdicts" / f"{a.second}.jsonl")}
        for r in rows(d / "kept_first" / "sft.jsonl"):
            if r.get("task") != "session" or r["id"] in seen:
                continue
            v = second.get(r["id"], {})
            if v.get("model_hard_fails"):
                continue
            scores = [judge._score(x) for x in (v.get("raw_scores") or {}).values()]
            pool.append((sum(s for s in scores if isinstance(s, (int, float))) if scores else -1, str(d), r["id"]))
    pool.sort(key=lambda x: (-x[0], x[1], x[2]))
    have, filled, chosen = collections.Counter(core), collections.Counter(), collections.defaultdict(set)
    for score, d, key in pool:
        need = [s for s in services.primary(people.get(person_of(key), {})) if have[s] < TARGET]
        if not need or key in seen:
            continue
        seen.add(key)
        chosen[d].add(key)
        for s in services.primary(people.get(person_of(key), {})):
            have[s] += 1
            filled[s] += 1
    for d in map(Path, a.dirs):
        keep = chosen.get(str(d), set())
        out = d / "kept"
        out.mkdir(exist_ok=True)
        with (out / "sft.jsonl").open("w") as f:
            for r in rows(d / "kept_both" / "sft.jsonl"):
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            for r in rows(d / "kept_first" / "sft.jsonl"):
                if r.get("task") in FILL_TASKS and session_of(r["id"]) in keep:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
        with (out / "pairs_spoken.jsonl").open("w") as f:
            for r in rows(d / "kept_both" / "pairs_spoken.jsonl"):
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            for r in rows(d / "kept_first" / "pairs_spoken.jsonl"):
                if session_of(r["id"]) in keep:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
    report = {"target": TARGET, "core_sessions": n_core,
              "filled_sessions": sum(len(v) for v in chosen.values()), "pool": len(pool),
              "per_service": {s.id: {"both judges": core[s.id], "filled": filled[s.id], "total": have[s.id]}
                              for s in services.SERVICES},
              "still_under_target": {s.id: have[s.id] for s in services.SERVICES if have[s.id] < TARGET}}
    Path(a.report).write_text(json.dumps(report, ensure_ascii=False, indent=1))
    print(json.dumps({k: report[k] for k in ("core_sessions", "filled_sessions", "pool", "still_under_target")}))


if __name__ == "__main__":
    main()
