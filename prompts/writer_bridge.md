# Bridging a gap of weeks or months in a long-term series

The person has been using a private therapy and coaching app for a long time: daily check-ins, weekly sessions,
practices. You are given their full profile, where they are in the long-term arc (the trajectory), today's point in
time, how long it has been since the state you are shown, and what the app remembered at that earlier point (or
"none" if this is the first point we see).

Write what the app would remember today, after all the sessions in between, as if those sessions really happened.
Make it consistent with the profile, the earlier state and the trajectory, and make it ordinary and specific:

- Real change is uneven. Over months some things improve and stay, some come back under stress, some goals are
  reached and replaced, habits are built or dropped, and new life events happen (a move, a loss, a new job, an
  illness in the family, a relationship). Follow the trajectory: steady means real gains kept with small dips;
  setback means a clear slip (old patterns back, lower mood) around this point; plateau means stuck for a while;
  slow_start means little change early, then real gains later.
- The story is written by the therapist about the person by name, under exactly these headings: About, Patterns
  and triggers, Beliefs we are working on, What helps, What does not help, Progress, Open threads. Under 350 words
  in total. What helps lists only things they have actually tried.
- The last note is the note of the most recent session before today (a day or a few days ago), in exactly the
  app's note format shown below, with "none" under any plan heading where nothing was added.
- Goals, habits and values are the ones the person has now; goals reached long ago are gone or replaced. Give
  each habit how many of the last 14 days it was kept (0 to 14), and each goal how many days ago it last moved.
- Scores are questionnaire results from the last few months, oldest first, matching the arc (PHQ-9 0 to 27,
  GAD-7 0 to 21).
- moods are the last seven days, oldest first, 0 to 10 or null for a day without a check-in.
- events is two to four sentences in the second person ("You..."), for the person to play: what happened recently
  and how they feel coming into today's session, including anything they may be reluctant to mention.

The app's note format:
Session: <daily checkin, weekly session or practice>, <weekday day month>
Talked about:
Practised:
Mood: start ?/10, end ?/10
Homework agreed:
Practice log: none, or lines like  commitment: ... | when: ...
Follow up next time:
Plan steps: none, or lines like  when: <day> <time> | step: ... | if-then: When ..., I will ... | they said: "..."
Habits: none
Goals: none
Values: none
Vision board: none
Safety: no concerns, or what was said and what was done

Answer with JSON only:
{"story": {"About": "...", "Patterns and triggers": "...", "Beliefs we are working on": "...", "What helps": "...",
           "What does not help": "...", "Progress": "...", "Open threads": "..."},
 "last_note": "...", "homework": "...", "moods": [n, n, null, n, n, n, n],
 "scores": ["PHQ-9 n, GAD-7 n", "..."],
 "goals": [{"text": "...", "next_step": "...", "days_since_progress": n}],
 "habits": [{"text": "...", "cue": "...", "tiny": "...", "kept_last_14": n}],
 "values": ["..."],
 "events": "..."}

Write everything in English, whatever the person's country or first language (the app is English in version 1).
