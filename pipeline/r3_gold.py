"""Round 3 (2026-11-19): the gold sessions written in the Claude Code session (helper, BRIEF_GOLD.md) -> series records
in the same shape as r3_write.py's, so r3_build.py treats them alike. Rendered with prompt v5 exactly as the app builds
it (formats.training_messages: the app prompt with the therapist's name and the fenced memory, the open event, turns).

  APP_PROMPT_VERSION=v5 python -I r3_gold.py --gold DIR --out DIR
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from formats import (APP_PROMPT_VERSION, STORY_HEADINGS, NOTE_HEADINGS, Memory, SessionSpec, Story,  # noqa: E402
                     name_from_about, note_instruction, story_instruction, training_messages, parse_headed)

assert APP_PROMPT_VERSION >= "v5"


def story_text(d: dict) -> str:
    return "\n".join(f"{h}: {d.get(h) or 'nothing yet'}" for h in STORY_HEADINGS)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    n, bad, names = 0, [], {}
    for p in sorted(Path(a.gold).glob("*.json")):
        try:
            g = json.loads(p.read_text())
            kind = g["kind"]
            mem = Memory(story=Story())
            m = g.get("memory")
            if m:
                mem = Memory(story=Story(sections={**Story().sections, **{k: str(v) for k, v in m["story"].items()
                                                                         if k in STORY_HEADINGS}}),
                             last_note=m.get("last_note", ""), homework_due=m.get("homework_due", ""),
                             sessions_done=int(m.get("sessions_done", 0)), since=m.get("since", ""),
                             programmes=[str(x) for x in m.get("programmes", [])],
                             moods=[x if x is None else int(x) for x in m.get("moods", [])],
                             scores=[str(x) for x in m.get("scores", [])])
            # the person's name as the app would hold it: stated in the file, or the name the record uses for them
            # (the About section, before the session for a later one, after it for a first one)
            mem.name = (g.get("person_name") or name_from_about((m or {}).get("story", {}).get("About", ""))
                        or name_from_about(g["story"].get("About", "")))
            assert mem.name, "no name for the person"
            names[p.stem] = mem.name
            spec = SessionSpec(kind=kind, date=g.get("date", "Thursday 19 November"), week=1, day=1,
                               therapist_name=g["therapist_name"], practice=g.get("practice", ""))
            turns = [(w, x) for w, x in g["turns"]]
            assert turns and turns[0][0] == "therapist", "must start with the therapist"
            session = training_messages(spec, mem, turns)
            note = g["note"].strip()
            # the note's first line as the app's note prompt gives it ("daily checkin", not "daily check-in")
            first, _, rest = note.partition("\n")
            if first.startswith("Session:"):
                first = first.replace("daily check-in", "daily checkin").replace("weekly-session", "weekly session")
            note = first + "\n" + rest
            missing = [h for h in NOTE_HEADINGS if not parse_headed(note, NOTE_HEADINGS).get(h) and f"{h}:" not in note]
            assert not missing, f"note lacks {missing}"
            note_msgs = session + [{"role": "user", "content": note_instruction(spec)}, {"role": "assistant", "content": note}]
            story = story_text(g["story"])
            story_msgs = [session[0], {"role": "user", "content": story_instruction() + "\n\nToday's note:\n" + note},
                          {"role": "assistant", "content": story}]
            rec = {"profile": g["profile_id"], "suffix": "G", "writer": {"model": "claude-code-gold", "mode": "script"},
                   "complete": True,
                   "sessions": [{"day": 1, "spec": {"kind": kind, "therapist_name": g["therapist_name"]}, "turns": turns,
                                 "training": {"session": session, "note": note_msgs, "story": story_msgs}}]}
            (out / f"gold_{p.stem}.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1))
            n += 1
        except Exception as e:  # report and go on
            bad.append(f"{p.name}: {e!r}")
    (out.parent / (out.name + "_names.json")).write_text(json.dumps(names, ensure_ascii=False, indent=0))
    print(f"{n} gold sessions converted; {len(bad)} refused")
    for b in bad:
        print("  ", b)


if __name__ == "__main__":
    main()
