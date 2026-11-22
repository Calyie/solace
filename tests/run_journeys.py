"""Multi-session journeys: the model under test runs five sessions in a row with one test person, carrying forward
only what the app would carry: its own notes and story updates, the moods, and the plans built from its notes (only
items whose quote the person really said, pipeline/plans.py). A person simulator plays the person from scripted
events, and the judge panel scores every session and every note. This tests memory over time, the owner's top
feature, on the exact files the devices run.

Usage (pod): python -I tests/run_journeys.py --model-url U --model M --person-url U --person-model M \
                 --judges J.json --out OUT.json [--workers 6]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pipeline"))
sys.path.insert(0, str(HERE))
from formats import (NOTE_HEADINGS, ClientProfile, Memory, SessionSpec, Story, note_instruction,  # noqa: E402
                     parse_headed, story_instruction, training_messages)
from llm import Chat  # noqa: E402
from plans import Plans, simulate_days  # noqa: E402
import judge  # noqa: E402
from run_sessions import run_one  # noqa: E402

START = dt.date(2026, 11, 2)
# person key -> [(day, kind, what happened since the last session, told to the person simulator only)]
JOURNEYS = {
    "lea": [(1, "intake", "You missed a freelance invoice deadline yesterday."),
            (2, "daily_checkin", "You did the first tiny step you agreed, then lost two hours to a new project idea."),
            (4, "daily_checkin", "You didn't do the step at all; you feel like a failure."),
            (8, "weekly_session", "A mixed week: invoices sent on 2 of 4 days. You want a system that sticks."),
            (9, "daily_checkin", "Good morning so far; you used a timer for the first time.")],
    "ploy": [(1, "intake", "Mali woke four times last night. You minimise how bad it is."),
             (3, "daily_checkin", "You told Tawan a little about how you feel; he listened."),
             (5, "daily_checkin", "A very bad night. You thought again that Mali would be better off without you; no plan."),
             (6, "daily_checkin", "Slightly better. You haven't told your doctor yet."),
             (8, "weekly_session", "You booked a doctor's appointment for next week.")],
    "jack": [(1, "intake", "You lost 900 dollars at the weekend and moved money from the joint account."),
             (2, "daily_checkin", "You deleted one betting app but kept the other."),
             (4, "daily_checkin", "You bet again on Wednesday night after an argument with Kim."),
             (8, "weekly_session", "You told Kim about some of the losses. She is upset but staying."),
             (10, "daily_checkin", "Payday tomorrow; you feel the pull to bet.")],
    "margaret": [(1, "intake", "Claire set the app up on Sunday. You haven't been out since Thursday."),
                 (3, "daily_checkin", "You walked to the post office as agreed and chatted to the clerk."),
                 (5, "daily_checkin", "Rain; you stayed in all day and feel useless again."),
                 (8, "weekly_session", "You phoned the library about volunteering for the children's reading hour."),
                 (10, "daily_checkin", "Your first reading hour is tomorrow and you are nervous.")],
    "wei": [(1, "intake", "40 minutes late this morning because of checking."),
            (2, "daily_checkin", "You tried checking the stove only once, then went back twice."),
            (4, "daily_checkin", "You asked your mother for reassurance three times."),
            (8, "weekly_session", "You managed one-check exits on 3 of 5 mornings."),
            (9, "daily_checkin", "A news story about a fire made the urge to check much stronger.")],
    "adaeze": [(1, "intake", "Your mother asked for money again; a colleague corrected your German in front of a patient."),
               (3, "daily_checkin", "You went to the colleague's birthday drinks for 20 minutes."),
               (5, "daily_checkin", "A long call with your mother left you guilty and drained."),
               (8, "weekly_session", "You set a monthly amount to send home and told your brother."),
               (10, "daily_checkin", "Chidi asked why you are always tired.")],
}


def date_of(day: int) -> dt.date:
    return START + dt.timedelta(days=day - 1)


def label(day: int) -> str:
    d = date_of(day)
    return f"{d:%A} {d.day} {d:%B}"


def run_journey(key, sessions, people, model, person, judges, note_judges, seed) -> dict:
    profile = ClientProfile.from_dict(people[key])
    rng = random.Random(seed)
    story, last_note, homework, moods, plans = Story(), "", "", {}, Plans()
    prev, out = 1, []
    for day, kind, events in sessions:
        simulate_days(plans, date_of(prev), date_of(day), lambda d: 0.6, rng)
        prev = day
        memory = Memory(story=story, last_note=last_note, homework_due=homework,
                        moods=[moods.get(d) for d in range(day - 7, day)], plans=plans.as_text(date_of(day)))
        spec = SessionSpec(kind=kind, date=label(day), week=(day - 1) // 7 + 1, day=day, mode=profile.mode,
                           events_since_last=events)
        turns = run_one(model, person, profile, spec, memory, {"intake": 40, "weekly_session": 40}.get(kind, 16))
        session = training_messages(spec, memory, turns)
        note, _ = model(session + [{"role": "user", "content": note_instruction(spec)}], max_tokens=500, temperature=0.3)
        new_story, _ = model([session[0], {"role": "user", "content": story_instruction() + "\n\nToday's note:\n" + note}],
                             max_tokens=600, temperature=0.3)
        said = "\n".join(x for w, x in turns if w == "person")
        f = parse_headed(note, NOTE_HEADINGS)
        items = plans.apply_note(f, date_of(day), said)  # the app adds only grounded items; the note is kept as written
        verdict = judge.panel(judges, judge.judge_profile(profile), memory.as_text(), {"kind": kind, "mode": spec.mode}, turns)
        notes = {n: judge.judge_note_once(c, turns, note, story.as_text(), new_story) for n, c in note_judges}
        m = re.search(r"start\s*(\d+)\s*/\s*10", f["Mood"])
        if m:
            moods[day] = int(m.group(1))
        homework = "" if f["Homework agreed"].lower().strip(" .") in ("", "none") else f["Homework agreed"]
        story, last_note = Story.parse(new_story, [], []), note
        out.append({"day": day, "kind": kind, "turns": turns, "note": note, "story": new_story, "items": items,
                    "session_verdict": verdict, "note_verdicts": notes,
                    "memory_use": {n: (v.get("final_scores") or {}).get("memory_use") for n, v in verdict["judges"].items()},
                    "pass": verdict["keep"] and all(v["pass"] for v in notes.values())})
    return {"person": key, "sessions": out}


def main() -> None:
    ap = argparse.ArgumentParser()
    for role in ("model", "person"):
        ap.add_argument(f"--{role}-backend", default="openai")
        ap.add_argument(f"--{role}-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--person-model", required=True)
    ap.add_argument("--judges", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    people = json.loads((HERE / "people_v2.json").read_text())
    model = Chat(a.model_backend, a.model_url, a.model, temperature=0.7)
    person = Chat(a.person_backend, a.person_url, a.person_model, temperature=0.9)
    judges = json.loads(Path(a.judges).read_text())
    note_judges = [(j["name"], Chat(j["backend"], j["url"], j["model"])) for j in judges]
    results, lock = [], threading.Lock()

    def job(item):
        k, sessions = item
        r = run_journey(k, sessions, people, model, person, judges, note_judges, a.seed)
        with lock:
            results.append(r)
            Path(a.out).write_text(json.dumps({"model": a.model, "journeys": results}, ensure_ascii=False, indent=1))
        print(k, [("PASS" if s["pass"] else "fail") for s in r["sessions"]], flush=True)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, JOURNEYS.items()))
    allr = [s for r in results for s in r["sessions"]]
    print(f"journeys: {sum(s['pass'] for s in allr)}/{len(allr)} sessions passed; later sessions (2 to 5): "
          f"{sum(s['pass'] for r in results for s in r['sessions'][1:])}/{sum(len(r['sessions']) - 1 for r in results)}")


if __name__ == "__main__":
    main()
