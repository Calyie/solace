"""Twelve-week journeys (TASKLIST A16; the owner's top feature is memory across sessions): the model under test runs
about sixteen sessions over twelve weeks with one test person, including a two-week break, carrying forward only
what the app would carry (tests/run_journeys.py run_journey: its own notes, story and plans). Three things are
measured, apart from the judges' verdicts on every session and note:

- retention: facts the person shares early ("planted") and whether the app's story still holds them after each
  later session (a code check on the story text);
- recall: moments where a later event connects to an early fact that the person does not repeat, and whether the
  therapist makes the connection (a code check on the therapist's words in that session);
- the pass rate by month, so a model that holds up in week 1 but drifts by week 10 shows.

Usage (GPU): python -I tests/run_long_journeys.py --model-url U --model M --person-url U --person-model M \
                 --judges J.json --out OUT.json [--workers 3]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pipeline"))
sys.path.insert(0, str(HERE))
from llm import Chat  # noqa: E402
from run_journeys import run_journey  # noqa: E402

# person -> [(day, kind, what happened since the last session, told to the person simulator only)]; days 30 to 42
# are a break with no sessions.
LONG = {
    "lea": [
        (1, "intake", "You missed a freelance invoice deadline yesterday. Mention that your grandmother, who raised "
                      "you, used to call you 'ma petite rêveuse', her little dreamer, and that it still stings and "
                      "comforts at once."),
        (2, "daily_checkin", "You did the first tiny step, then lost two hours to a new project idea."),
        (4, "daily_checkin", "You used a kitchen timer for twenty minutes and it worked."),
        (8, "weekly_session", "Invoices sent on 2 of 4 days. Your flatmate Inès offered to work beside you on Sundays."),
        (11, "daily_checkin", "Sunday with Inès went well: three invoices sent."),
        (15, "weekly_session", "Marc praised a design in front of the team; you felt like a fraud."),
        (22, "weekly_session", "A bad week: you lost your phone twice and missed a client call."),
        (29, "weekly_session", "You are going to Grenoble for two weeks to help your mother move house."),
        (43, "weekly_session", "Back after the break. The routine fell apart while you were away and you feel "
                               "ashamed to come back."),
        (44, "daily_checkin", "You restarted the timer, ten minutes only."),
        (50, "weekly_session", "A client asked for a big new project; you want to say yes to everything."),
        (57, "weekly_session", "Your grandmother's birthday is on Friday; you have not called her in a month."),
        (64, "weekly_session", "You finished a whole project on time for the first time this year."),
        (71, "weekly_session", "Marc offered you a lead role; you are scared you will drop the ball."),
        (78, "weekly_session", "Twelve weeks in. You want to look back at what changed."),
    ],
    "wei": [
        (1, "intake", "40 minutes late this morning because of checking. Mention that it got much worse after the "
                      "kitchen fire at Mr Tan's flat downstairs when you were at university."),
        (2, "daily_checkin", "You tried checking the stove once, then went back twice."),
        (4, "daily_checkin", "You asked your mother for reassurance three times."),
        (8, "weekly_session", "One-check exits on 3 of 5 mornings. Siew Lin is losing patience."),
        (15, "weekly_session", "You left the house without checking the taps and the anxiety faded after an hour."),
        (16, "daily_checkin", "A colleague, Hafiz, joked about you being late again."),
        (22, "weekly_session", "You and Siew Lin are looking at a flat together; the gas stove there frightens you."),
        (29, "weekly_session", "Work audit season starts; you will be very busy for two weeks."),
        (43, "weekly_session", "Back after the busy weeks. Checking crept back up under the stress."),
        (45, "daily_checkin", "A smoke alarm went off in your office building (a false alarm)."),
        (50, "weekly_session", "You moved into the new flat with Siew Lin."),
        (57, "weekly_session", "You cooked dinner on the gas stove and left for a walk without going back."),
        (64, "weekly_session", "Your mother is visiting and keeps asking whether you switched things off."),
        (71, "weekly_session", "You were on time every day this week."),
        (78, "weekly_session", "Twelve weeks in. You want to plan how to keep going on your own."),
    ],
    "margaret": [
        (1, "intake", "Claire set the app up on Sunday. You haven't been out since Thursday. Mention that Derek used "
                      "to do the crossword with you every evening at seven, and evenings are the worst."),
        (3, "daily_checkin", "You walked to the post office as agreed and chatted to the clerk."),
        (5, "daily_checkin", "Rain; you stayed in all day and feel useless again."),
        (8, "weekly_session", "You phoned the library about volunteering for the children's reading hour."),
        (15, "weekly_session", "Your first reading hour went well; a shy boy asked you to read again."),
        (22, "weekly_session", "Pat from next door has a fall and is in hospital."),
        (29, "weekly_session", "Claire is taking you to Bristol for two weeks over the half-term."),
        (43, "weekly_session", "Home again; the house feels very quiet after Bristol."),
        (45, "daily_checkin", "You found a crossword book in a drawer this evening and cried."),
        (50, "weekly_session", "Pat is home; you took her a casserole."),
        (57, "weekly_session", "The anniversary of Derek's death is next week."),
        (64, "weekly_session", "You went to the anniversary lunch with Claire and Ollie; it was sad but warm."),
        (71, "weekly_session", "The library asked you to run the reading hour twice a week."),
        (78, "weekly_session", "Twelve weeks in. You want to talk about how far you've come."),
    ],
}
# Planted facts: (person, the day it is first said, a name, words that show the story still holds it)
FACTS = [("lea", 1, "grandmother's 'little dreamer'", r"r[êe]veuse|dreamer"),
         ("lea", 8, "Sundays working beside Inès", r"In[èe]s"),
         ("wei", 1, "the fire at Mr Tan's flat", r"Mr Tan|fire"),
         ("wei", 22, "the gas stove in the new flat", r"gas|stove"),
         ("margaret", 1, "the crossword with Derek at seven", r"crossword"),
         ("margaret", 8, "the library reading hour", r"library|reading hour")]
# Recall opportunities: (person, day, what links back, words in the therapist's turns that show the link)
RECALL = [("lea", 57, "the grandmother who called her her little dreamer", r"r[êe]veuse|dreamer|raised you"),
          ("lea", 43, "the Sunday sessions with Inès or the timer that worked", r"In[èe]s|timer"),
          ("wei", 45, "the fire at Mr Tan's flat", r"Mr Tan|downstairs|university"),
          ("wei", 57, "his fear of the gas stove at the new flat", r"frighten|scared|afraid|fear|before|used to"),
          ("margaret", 45, "the crossword with Derek at seven", r"Derek|seven|evening"),
          ("margaret", 57, "Derek and the evenings", r"crossword|seven|evening")]


def measure(r: dict) -> dict:
    key, sessions = r["person"], r["sessions"]
    days = [s["day"] for s in sessions]
    retention = {}
    for p, day, name, rx in FACTS:
        if p != key:
            continue
        later = [bool(re.search(rx, s["story"], re.I)) for s in sessions if s["day"] >= day]
        retention[name] = {"held": sum(later), "of": len(later), "last": later[-1] if later else None}
    recall = {}
    for p, day, what, rx in RECALL:
        if p == key and day in days:
            s = sessions[days.index(day)]
            said = " ".join(x for w, x in s["turns"] if w == "therapist")
            recall[what] = bool(re.search(rx, said, re.I))
    by_month = {}
    for s in sessions:
        m = min(3, (s["day"] - 1) // 28 + 1)
        by_month.setdefault(m, []).append(s["pass"])
    return {"retention": retention, "recall": recall,
            "pass_by_month": {m: f"{sum(v)}/{len(v)}" for m, v in sorted(by_month.items())}}


def main() -> None:
    ap = argparse.ArgumentParser()
    for role in ("model", "person"):
        ap.add_argument(f"--{role}-backend", default="openai")
        ap.add_argument(f"--{role}-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--person-model", required=True)
    ap.add_argument("--judges", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--seed", type=int, default=5)
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
        r["measures"] = measure(r)
        with lock:
            results.append(r)
            Path(a.out).write_text(json.dumps({"model": a.model, "journeys": results}, ensure_ascii=False, indent=1))
        print(k, json.dumps(r["measures"], ensure_ascii=False), flush=True)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, LONG.items()))
    held = [v["last"] for r in results for v in r["measures"]["retention"].values() if v["last"] is not None]
    rec = [v for r in results for v in r["measures"]["recall"].values()]
    allr = [s["pass"] for r in results for s in r["sessions"]]
    print(f"long journeys: {sum(allr)}/{len(allr)} sessions passed; early facts still in the story at the end "
          f"{sum(held)}/{len(held)}; recall moments taken {sum(rec)}/{len(rec)}")


if __name__ == "__main__":
    main()
