"""Checks for pipeline/plans.py and the v2 note format. Run: python -I tests/test_plans.py"""
import datetime as dt
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
from formats import NOTE_HEADINGS, parse_headed, parse_split, split_instruction, template  # noqa: E402
from plans import Plans, grounded, parse_items, parse_when, simulate_days  # noqa: E402

WED = dt.date(2026, 11, 18)

# when: today, tomorrow, weekdays (the same weekday means next week), this week, times
assert parse_when("today 10:00", WED) == ("2026-11-18", "10:00")
assert parse_when("Tonight 9.30", WED) == ("2026-11-18", "09:30")
assert parse_when("tomorrow", WED) == ("2026-11-19", "")
assert parse_when("Friday 18:30", WED) == ("2026-11-20", "18:30")
assert parse_when("Wednesday 8:05", WED) == ("2026-11-25", "08:05")
assert parse_when("Monday", WED) == ("2026-11-23", "")
assert parse_when("this week", WED) == ("", "")

# grounded: the person's words, ignoring case and punctuation; one word is not enough
said = "Honestly? I'd like to SKETCH again, maybe on Sunday mornings.\nYeah, after coffee I could start."
assert grounded("I'd like to sketch again", said)
assert grounded("after coffee, I could start", said)
assert not grounded("sketch", said)
assert not grounded("I love sketching", said)
assert not grounded("", said)
assert grounded("je voudrais dessiner le dimanche", "Oui, je voudrais dessiner le dimanche matin au café.")
assert grounded("ọ dị mma", "Ọ dị mma, m ga-anwa ya.")  # Igbo letters with dots below
assert not grounded("le café", "le cafe")  # accents count, as in the app
assert grounded("spend more time with Amani without... being so needy",
                "I want to spend more time with Amani without... I don't know, without being so needy.")
assert not grounded("being so needy... spend more time", "spend more time with Amani without being so needy")  # order
assert not grounded("... yes ...", "yes")  # pieces must add up to two words


NOTE = """Session: weekly session, Wednesday 18 November
Talked about: sketching again.
Practised: planning.
Mood: start 5/10, end 6/10
Homework agreed: sketch on Sunday.
Practice log: none
Follow up next time: how Sunday went.
Plan steps:
- when: Sunday 10:00 | step: Sketch at the cafe for 20 minutes | if-then: When I finish breakfast, I will take the sketchbook | they said: "maybe on Sunday mornings"
- when: today | step: Buy a new sketchbook | they said: "I need a new notebook"
Habits: habit: Ten minutes of sketching | cue: after coffee | tiny version: one doodle | they said: "after coffee I could start"
Goals: none
Values: value: creativity | they said: "I'd like to sketch again"
Vision board: none
Safety: no concerns"""
f = parse_headed(NOTE, NOTE_HEADINGS)
assert [r["kind"] for r in parse_items(f["Plan steps"])] == ["when", "when"]
plans = Plans()
log = plans.apply_note(f, WED, said)
assert [(x["kind"], x["added"]) for x in log] == [("when", True), ("when", False), ("habit", True), ("value", True)], log
assert log[1]["why"] == "quote not found in what they said"
assert plans.steps[0].day == "2026-11-22" and plans.steps[0].time == "10:00"
assert plans.habits[0].start == "2026-11-18" and plans.habits[0].tiny == "one doodle"

# a step with no description is not added
assert Plans().apply_note({"Plan steps": 'when: today 10:00 | they said: "after coffee I could start"'}, WED, said)[0]["why"] == "no item"

# planning the same open step again moves it instead of adding a second one
again = {"Plan steps": 'when: Monday | step: sketch at the cafe for 20 minutes | they said: "maybe on Sunday mornings"'}
plans.apply_note(again, WED, said)
assert len(plans.steps) == 1 and plans.steps[0].moves == 1 and plans.steps[0].day == "2026-11-23"

# noticed: missed the last two Tuesdays; missed yesterday; kept 12 of 14; stalled goal; old picture; at most three
p = Plans.from_dict({"habits": [
    {"text": "A", "start": "2026-11-01", "missed": ["2026-11-10", "2026-11-17"]},
    {"text": "B", "start": "2026-11-01", "missed": ["2026-11-17"]},
    {"text": "C", "start": "2026-11-01", "kept": [f"2026-11-{d:02d}" for d in range(4, 18)]}]})
assert p.noticed(WED) == ["A was missed on the last two Tuesdays", "B was missed yesterday", "C was kept on 14 of the last 14 days"], p.noticed(WED)
p = Plans.from_dict({"goals": [{"text": "G", "last_progress": "2026-11-01"}], "pictures": [{"title": "P", "added": "2026-10-10"}],
                     "steps": [{"text": "S", "day": "2026-11-19", "moves": 3}]})
assert p.noticed(WED) == ['"S" has been moved 3 times', 'goal "G": no progress in 17 days', 'vision board "P": nothing done in 39 days']

# the rendered block: empty step rows are left out, the others say none
text = Plans().as_text(WED)
assert text.splitlines()[1:] == ["Today's plan: none", "Habits: none", "Goals: none", "Values: none", "Vision board: none",
                                 "Noticed by the app: none"], text

# the stand-in for the days in between is reproducible and fills the record
a, b = Plans.from_dict(plans.to_dict()), Plans.from_dict(plans.to_dict())
for x in (a, b):
    simulate_days(x, WED, WED + dt.timedelta(days=21), lambda d: 0.7, random.Random(4))
assert a.to_dict() == b.to_dict() and len(a.habits[0].kept) + len(a.habits[0].missed) == 21

# help me start: the instruction and the reader
assert "Task: Lavoie details" in split_instruction("Lavoie details")
assert parse_split("1. Open the file | 2 min\n2) Trace the grid | 8 min\nnot a step\n3. Stop|5 min") == [
    ("Open the file", 2), ("Trace the grid", 8), ("Stop", 5)]

# the v2 note template names every heading the parser expects, in order
tpl = template("app_note")
assert [h for h in NOTE_HEADINGS if f"\n{h}:" in tpl] == NOTE_HEADINGS
# clean_note: ungrounded items are taken out; an emptied heading says none; other headings are untouched
from plans import clean_note  # noqa: E402
cleaned, dropped = clean_note(NOTE, said)
assert dropped == ['- when: today | step: Buy a new sketchbook | they said: "I need a new notebook"'], dropped
assert "Buy a new sketchbook" not in cleaned and "Sketch at the cafe" in cleaned and cleaned.endswith("Safety: no concerns")
c2, d2 = clean_note('Goals: goal: Run | they said: "I love running"\nValues: none\nSafety: ok', "nothing")
assert c2 == "Goals: none\nValues: none\nSafety: ok" and len(d2) == 1, c2

print("plans tests: all passed")
