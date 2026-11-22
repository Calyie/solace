"""Write reference renderings for the app's tests: the app must build exactly the same prompt text the model was
trained on, so these come from the Python training code and the Dart tests compare character by character.

Also copies the app prompt templates and the single-reply probes into the app, so both sides use one source.
Usage: python -I tests/make_app_fixtures.py
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
sys.path.insert(0, str(ROOT / "tests"))
import datetime as dt  # noqa: E402
from formats import (APP_PROMPT_VERSION, NOTE_HEADINGS, SessionSpec, app_system, note_instruction,  # noqa: E402
                     parse_headed, parse_split, split_instruction, story_instruction)
from plans import Plans, grounded, parse_when  # noqa: E402
from run_probes import memory_for  # noqa: E402

APP = ROOT / "app"
(APP / "assets" / "prompts").mkdir(parents=True, exist_ok=True)
(APP / "test" / "fixtures").mkdir(parents=True, exist_ok=True)
for name in ("app_system", "app_note", "app_story"):
    shutil.copy(ROOT / "prompts" / f"{name}_{APP_PROMPT_VERSION}.txt", APP / "assets" / "prompts")
shutil.copy(ROOT / "prompts" / "app_split_v1.txt", APP / "assets" / "prompts")
shutil.copy(ROOT / "tests" / "probes_v2.jsonl", APP / "test" / "fixtures")

presets = json.loads((ROOT / "tests" / ("memories_v5.json" if APP_PROMPT_VERSION >= "v5" else "memories_v2.json")).read_text())
cases = []
for key, pre in presets.items():
    kinds = ["intake"] if key == "first" else ["daily_checkin", "weekly_session", "practice"]
    if pre["mode"] == "full":
        kinds += ["reliving", "written_exposure"]
    for kind in kinds:
        spec = SessionSpec(kind=kind, date=pre["date"], week=0, day=0, mode=pre["mode"])
        mem = memory_for(pre)
        cases.append({"preset": key, "kind": kind, "mode": pre["mode"], "date": pre["date"], "today": pre.get("today", ""),
                      "memory": pre["memory"],
                      "memory_text": mem.as_text(), "app_system": app_system(spec, mem),
                      "note_instruction": note_instruction(spec), "story_instruction": story_instruction()})
# The first message with the check-in before the session (v4, 2026-11-07; formats.open_event), for test/formats_test.dart
if APP_PROMPT_VERSION >= "v4":
    from formats import open_event  # noqa: E402
    check_ins = [None, {}, {"skipped": True}, {"mood": 6, "safety": "fine"}, {"safety": "thoughts"}, {"mood": 0, "safety": "help"},
                 {"mood": 4, "practice": "the lift ladder, step 2", "start": 70, "end": 35, "safety": "fine"},
                 {"practice": "touching the door handle", "safety": ""}, {"mood": 10}]
    opens = [{"practice": pr, "check_in": c, "open_event": open_event(pr, c)}
             for pr in ("", "Box breathing") for c in check_ins]
    (APP / "test" / "fixtures" / f"open_{APP_PROMPT_VERSION}.json").write_text(json.dumps(opens, ensure_ascii=False, indent=1))
    print(f"{len(opens)} first messages with check-ins -> open_{APP_PROMPT_VERSION}.json")
out = APP / "test" / "fixtures" / f"render_{APP_PROMPT_VERSION}.json"
out.write_text(json.dumps(cases, ensure_ascii=False, indent=1))
print(f"{len(cases)} reference renderings -> {out}")

# Plans (pipeline/plans.py): rendering, noticing, reading notes, dates, quotes and task splits, for test/plans_test.dart
WED = dt.date(2026, 11, 18)
render = []
for key, pre in presets.items():
    if pre["memory"].get("plans") is not None:
        pl, day = Plans.from_dict(pre["memory"]["plans"]), dt.date.fromisoformat(pre["today"])
        render.append({"name": key, "plans": pre["memory"]["plans"], "today": pre["today"], "text": pl.as_text(day),
                       "noticed": pl.noticed(day)})
synthetic = {
    "habits": {"habits": [{"text": "A", "start": "2026-11-01", "missed": ["2026-11-10", "2026-11-17"]},
                          {"text": "B", "start": "2026-11-01", "missed": ["2026-11-17"], "cue": "lunch"},
                          {"text": "C", "start": "2026-11-01", "kept": [f"2026-11-{d:02d}" for d in range(4, 18)],
                           "tiny": "one page"}]},
    "steps": {"steps": [{"text": "S", "day": "2026-11-19", "moves": 3}, {"text": "T", "day": "2026-11-18", "time": "09:00",
               "status": "done"}, {"text": "U", "day": "2026-11-18"}, {"text": "V", "day": "2026-11-12", "ifthen": "When x, I will y"},
              {"text": "W", "day": "2026-11-11"}, {"text": "X", "day": "2026-11-10", "moves": 1}, {"text": "Y", "day": "2026-11-09"},
              {"text": "Z"}, {"text": "D", "day": "2026-11-18", "status": "dropped"},
              {"text": "E", "day": "2026-11-16", "status": "done"}, {"text": "F", "day": "2026-11-11", "status": "done"},
              {"text": "H", "day": "2026-11-10", "status": "done"}],
              "goals": [{"text": "G", "last_progress": "2026-11-01", "next_step": "call"}],
              "pictures": [{"title": "P", "added": "2026-10-10", "plan": "If a, then b"}],
              "values": [{"text": "kindness"}]},
    "empty": {},
}
for name, d in synthetic.items():
    pl = Plans.from_dict(d)
    render.append({"name": name, "plans": pl.to_dict(), "today": WED.isoformat(), "text": pl.as_text(WED),
                   "noticed": pl.noticed(WED)})
said = "Honestly? I'd like to SKETCH again, maybe on Sunday mornings.\nYeah, after coffee I could start. Ọ dị mma."
note = """Plan steps:
- when: Sunday 10:00 | step: Sketch at the cafe for 20 minutes | if-then: When I finish breakfast, I will take the sketchbook | they said: "maybe on Sunday mornings"
- when: today | step: Buy a new sketchbook | they said: "I need a new notebook"
- when: tomorrow 7.30 | they said: "after coffee I could start"
Habits: habit: Ten minutes of sketching | cue: after coffee | tiny version: one doodle | they said: "after coffee I could start"
Goals: goal: "Draw for fun again" | next step: buy pencils | they said: “I'd like to sketch again”
Values: value: creativity | they said: "I'd like to sketch again"
- value: Creativity | they said: "ọ dị mma"
Vision board: picture: Sundays with a sketchbook | wish: sketch weekly | outcome: feel like myself | obstacle: scrolling | plan: If I reach for the phone, then I will open the sketchbook | they said: "on Sunday mornings"
Safety: no concerns"""
apply_cases = []
before = Plans.from_dict({"steps": [{"text": "sketch at the cafe for 20 minutes", "day": "2026-11-15", "added": "2026-11-11"}],
                          "goals": [{"text": "Draw for fun again", "next_step": "find a sketchbook", "last_progress": "2026-11-04"}]})
for b in (Plans(), before):
    pl = Plans.from_dict(b.to_dict())
    log = pl.apply_note(parse_headed(note, NOTE_HEADINGS), WED, said)
    apply_cases.append({"before": b.to_dict(), "note": note, "today": WED.isoformat(), "person": said, "log": log,
                        "after": pl.to_dict(), "text": pl.as_text(WED)})
whens = [[t, d, *parse_when(t, dt.date.fromisoformat(d))] for t, d in [
    ("today 10:00", "2026-11-18"), ("Tonight 9.30", "2026-11-18"), ("tomorrow", "2026-11-18"), ("Friday 18:30", "2026-11-18"),
    ("Wednesday 8:05", "2026-11-18"), ("monday", "2026-11-22"), ("this week", "2026-11-18"), ("Sunday 25:00", "2026-11-18"),
    ("at 7h15 on Saturday", "2026-11-16")]]
quotes = [[q, t, grounded(q, t)] for q, t in [
    ("I'd like to sketch again", said), ("sketch", said), ("I love sketching", said), ("", said),
    ("je voudrais dessiner le dimanche", "Oui, je voudrais dessiner le dimanche matin au café."),
    ("le café", "le cafe"), ("ọ dị mma", said), ("After coffee,  I could START", said),
    ("I'd like to... Sunday mornings", said), ("Sunday mornings... I'd like to", said), ("... yes ...", "yes"),
    ("SKETCH again… maybe on Sunday", said)]]
splits = [[t, parse_split(t)] for t in ["1. Open the file | 2 min\n2) Trace the grid | 8 min\nnot a step\n3. Stop|5 min", "none"]]
(APP / "test" / "fixtures" / f"plans_{APP_PROMPT_VERSION}.json").write_text(json.dumps(
    {"render": render, "apply": apply_cases, "when": whens, "grounded": quotes, "split": splits,
     "split_instruction": split_instruction("Lavoie details")}, ensure_ascii=False, indent=1))
print(f"{len(render)} plan renderings, {len(apply_cases)} note cases -> plans_{APP_PROMPT_VERSION}.json")
