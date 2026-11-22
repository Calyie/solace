"""Second-version notes (owner 2026-11-04, option B). The second judge passed only about 28 percent of the notes the
first judge passed, for real faults: plan details the person never agreed to, wrong mood numbers, invented
practice-log figures. For every session both judges approved whose note did not pass both, the writer writes the note
again with extra accuracy rules that only the writer sees, and the story is rewritten from the new note. The training
example keeps the app's own note instruction (unchanged), so the on-device model learns the stricter habit from the
app's prompt. Both judges then check the new notes (the second only those the first passed); combine prefers a new
note that passes both.

  python -I pipeline/notes_v2.py write --out-dir D --url U --model gemma26b --workers 96
  python -I pipeline/notes_v2.py judge --out-dir D --judge-name gemma26b --url U --model gemma26b --workers 64
  python -I pipeline/notes_v2.py judge --out-dir D --judge-name gptoss --url U --model gptoss --after gemma26b
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from formats import story_instruction  # noqa: E402
from llm import Chat  # noqa: E402
from plans import clean_note  # noqa: E402
import batch  # noqa: E402
import judge  # noqa: E402
import series  # noqa: E402

NAMES = ["gemma26b", "gptoss"]
STRICT = """Extra rules for this note (being accurate matters more than being complete):
- Mood: write a number only if the person gave that number for how they feel overall, in this session. A rating of
  something else (distress, a body feeling, tiredness, confidence) is not their mood. If they were not asked, write
  "not asked"; if they would not give a number, write "declined".
- Plan steps, habits, goals, values and vision board: only what the person clearly agreed to in this session, with
  only the details they agreed to (day, time, cue). Never add a day or time they did not agree to. The words after
  "they said:" must be their exact words from this session.
- Practice log: only commitments, predictions, outcomes and confidence figures the person said in this session, with
  their own numbers; otherwise "none".
- Homework agreed: only what was agreed in this session.
- Add nothing that was not said in this session."""


def sessions(out: Path) -> dict[str, dict]:
    found = {}
    for f in sorted((out / "series").glob("*.json")):
        rec = json.loads(f.read_text())
        for i, s in enumerate(rec["sessions"]):
            found[f"{rec['profile']}{rec.get('suffix', '')}#{i}"] = s
    return found


def todo_keys(out: Path) -> list[str]:
    """Sessions both judges approved (with the safety re-check) whose original note did not pass both."""
    v, cascade, ss, keys = batch.load_verdicts(out, NAMES), batch.cascade_judges(out), sessions(out), []
    for key, s in ss.items():
        rows = [v[n].get(key) for n in NAMES]
        if any(r is None for r in rows):
            continue
        safe_s, safe_n = batch.safety_recheck(s, s["training"]["note"][-1]["content"])
        if not (safe_s and all(batch.session_ok(n, r, s["spec"]["kind"], cascade) for n, r in zip(NAMES, rows))):
            continue
        if not (safe_n and all(r["note_pass"] for r in rows)):
            keys.append(key)
    return keys


def write(a) -> None:
    out = Path(a.out_dir)
    dest = out / "notes_v2.jsonl"
    done = {json.loads(l)["key"] for l in dest.read_text().splitlines() if l.strip()} if dest.exists() else set()
    ss, chat, lock = sessions(out), Chat(a.backend, a.url, a.model), threading.Lock()
    keys = [k for k in todo_keys(out) if k not in done][: a.limit or None]
    print(f"{len(keys)} notes to write again ({len(done)} done)", flush=True)

    def job(key):
        s = ss[key]
        msgs = s["training"]["note"][:-1]  # the app's session and note instruction
        ask = msgs[:-1] + [{"role": "user", "content": msgs[-1]["content"] + "\n\n" + STRICT}]
        try:
            note, _ = chat(ask, max_tokens=500, temperature=0.3)
            note, dropped = clean_note(note, series.person_text(s["turns"]))
            story_ask = story_instruction() + "\n\nToday's note:\n" + note
            story, _ = chat([s["training"]["story"][0], {"role": "user", "content": story_ask}], max_tokens=600,
                            temperature=0.3)
        except Exception as e:  # nothing written: a rerun tries again
            print(f"{key}: ERROR {type(e).__name__}: {str(e)[:120]}", flush=True)
            return
        with lock, dest.open("a") as f:
            f.write(json.dumps({"key": key, "note": note, "dropped": dropped, "story_ask": story_ask, "story": story},
                               ensure_ascii=False) + "\n")

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, keys))


def judge_notes(a) -> None:
    out = Path(a.out_dir)
    dest = out / "verdicts" / f"notes_v2_{a.judge_name}.jsonl"
    done = {json.loads(l)["key"] for l in dest.read_text().splitlines() if l.strip()} if dest.exists() else set()
    first = batch.load_verdicts(out, [a.after], "notes_v2_")[a.after] if a.after else None
    rows = [json.loads(l) for l in (out / "notes_v2.jsonl").read_text().splitlines() if l.strip()]
    rows = [r for r in rows if r["key"] not in done and (first is None or first.get(r["key"], {}).get("note_pass"))]
    ss, chat, lock = sessions(out), Chat(a.backend, a.url, a.model), threading.Lock()
    print(f"{len(rows)} new notes to judge with {a.judge_name} ({len(done)} done)", flush=True)

    def job(r):
        s = ss[r["key"]]
        mem = judge.memory_from_system(s["training"]["session"][0]["content"])
        try:
            nv = judge.judge_note_once(chat, s["turns"], r["note"], mem.split("Last session note:")[0], r["story"])
        except Exception as e:
            print(f"{r['key']}: ERROR {type(e).__name__}: {str(e)[:120]}", flush=True)
            return
        with lock, dest.open("a") as f:
            f.write(json.dumps({"key": r["key"], "note_pass": nv["pass"], "note_scores": nv.get("scores"),
                                "note_hard_fails": nv.get("hard_fails", [])}, ensure_ascii=False) + "\n")

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, rows))
    got = [json.loads(l) for l in dest.read_text().splitlines() if l.strip()]
    print(f"{a.judge_name}: {sum(x['note_pass'] for x in got)} of {len(got)} new notes passed", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("job", choices=["write", "judge", "count"])
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--backend", default="openai")
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--model", default="gemma26b")
    ap.add_argument("--judge-name", default="")
    ap.add_argument("--after", default="", help="judge only the new notes this judge passed")
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--limit", type=int, default=0, help="write only this many (a smoke test)")
    a = ap.parse_args()
    if a.job == "count":
        print(len(todo_keys(Path(a.out_dir))), "notes to write again")
    else:
        write(a) if a.job == "write" else judge_notes(a)


if __name__ == "__main__":
    main()
