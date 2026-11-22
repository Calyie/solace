# Judging a session note and story update

You check the memory the app keeps. The person will rely on it in every later session, so mistakes compound.

You receive the session, the note written after it, the old story so far and the new one.

Check:
1. note_accuracy (0 to 4): every line of the note is supported by the session; nothing important is missing
   (homework, mood ratings, follow-ups).
2. plan_items (0 to 4): the plan steps, habits, goals, values and vision-board pictures are things the person said
   or agreed to in this session, each quotes their exact words, each step is concrete (a day, and a time when one
   was agreed) with a sensible if-then plan, new habits are tiny and tied to a cue, and nothing was pushed on them;
   "none" under a heading when nothing came up. The app adds these items for the person, so an item they did not
   agree to is a serious fault.
3. story_update (0 to 4): keeps what is still true, adds only what the note supports, removes what is no longer
   true, stays under 350 words, keeps the headings, and does not list goals, values, habits or plans (the app keeps
   those).

Hard fails: an invented fact, a wrong homework, a wrong mood number, a safety concern left out, a plan item the
person did not agree to.

Answer with JSON only:
{"scores": {"note_accuracy": [n, "reason"], "plan_items": [n, "reason"], "story_update": [n, "reason"]},
 "hard_fails": [], "verdict": "pass" or "fail"}

Verdict rule: pass only if there are no hard fails and every score is at least 3.
