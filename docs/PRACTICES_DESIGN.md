# Practices that actually change things

## Update, same day: two separate features (owner's direction)

The owner pointed out that turning meditation into daily exercises becomes one more thing to put off and dread.
So there are two features:

1. Meditate (the main one): listen-only. Press play, nothing to fill in, no ratings required. Built on three routes
   with evidence that work without effort: the body (cyclic sighing: five minutes a day lifted mood more than
   mindfulness meditation in a 2023 Stanford trial; slow breathing near six breaths a minute reduces stress and
   anxiety), imagery (compassion-focused imagery for self-criticism; a visit from the future self; savouring a real
   good moment), and deep relaxation (guided hypnosis, which reduced anxiety substantially across studies; deep rest;
   a sleep technique). Each one is quietly personalised from memory (approved values and goals, today's focus) and from
   optional words in Settings, never from the third-person story. The Morning lift names the day's focus in four
   minutes of listening. Each meditation shows its evidence honestly. Built by app/tool/build_library_v2.py.
2. Programmes (optional exercises): everything below, for people who choose to work on something specific.

Written 2026-10-29 at the owner's request: practices must not be generic, passive meditations; someone who does the
morning focus practice should find their focus that day, and weeks of practice should bring the change promised.

## What makes a practice work

Passive listening to a calm voice has modest effects. The ingredients below are the ones with the best evidence, and
each practice is built from them.

1. Personal: it uses the person's own goal, fear, critical thought, people and the real moments coming up today,
   taken from the app's memory and from what they say now. Never a generic beach or "your goals".
2. Active: the person answers, chooses, says things aloud, writes one line. Vivid first-person rehearsal of the real
   moment later today ("you are at your desk, it is 9:00...") and role-play with the therapist (who can play the
   manager, the partner, the critic) make it involving.
3. Ends in action today: one concrete step with an if-then plan ("If it is 9:00 and I open my laptop, then I write the
   first paragraph before email"). Implementation intentions have a medium-to-large effect on goal attainment across
   94 studies (Gollwitzer and Sheeran, 2006). Mental contrasting (WOOP: wish, outcome, obstacle, plan; Oettingen)
   adds the inner obstacle and the plan for it.
4. The loop closes: in the evening or at the next check-in, what happened, and what happened compared with what was
   predicted. In anxiety, the gap between the feared outcome and the real one drives the learning (inhibitory
   learning, Craske and others, 2014). In low mood, people predict less enjoyment than they get; seeing that gap is
   part of behavioural activation.
5. Visible accumulation: each programme has its own evidence of change (commitments kept, fears that came true,
   pieces of evidence collected, activities done, urges resisted), shown in Progress beside mood and questionnaires.
6. A programme, not a one-off: daily, progressive (next ladder step, deeper value), varied in technique so it does
   not go stale, and designed for weeks to months: forming a habit took a median of 66 days in Lally and others
   (2010). Missed days are expected and handled without shame.

Honest limits: none of this works without repetition and real-world action, and for clinical depression or anxiety it
complements therapy rather than replacing it. Some well-known exercises (gratitude lists, for example) have small
effects on their own; they are kept as parts of programmes, not promised as cures.

## The daily loop (5 to 10 minutes in the morning, 1 minute in the evening)

1. Arrive (about a minute): one slow breath with a longer out-breath, notice the body, rate today's target from 0 to
   10 (focus, anxiety, mood, self-worth, stuckness).
2. Look back (seconds): yesterday's commitment or prediction and what actually happened.
3. Core technique (3 to 6 minutes): active and personal (below).
4. Rehearse (1 to 2 minutes): imagine the specific moment today in first person, present tense, with the body; meet
   the obstacle; carry out the if-then.
5. Commit: one concrete action today, said aloud; the app saves it and shows it on Today all day.
6. Re-rate.
Evening (or the next check-in): did it happen, what happened, one thing learned. The app records it.

## The programmes

| Programme | Core technique each morning | Evening question | Evidence of change shown |
|---|---|---|---|
| Morning focus and purpose | Choose today's value; "what would make today a good day, in one sentence"; WOOP; the first two-minute step; rehearse starting | Did the one thing happen? What pulled you away? | Commitments kept; "meaningful day" ratings; the purpose thread across weeks |
| Courage ladder (anxiety, fear) | Today's step from the person's ladder (built with the therapist, distress 0 to 100); write the feared outcome and how sure (0 to 100%); name safety behaviours to drop; rehearse doing it while letting anxiety be there | What happened compared with the prediction? Peak distress? | Ladder steps climbed; fears that came true (usually few); peak distress falling |
| Letting thoughts pass (worry, obsessive thinking) | Detached mindfulness with today's actual thought; attention training (switching between sounds); set today's worry time; for urges to check or seek reassurance: name the urge, delay it, watch it rise and fall | Urges resisted? Minutes lost to worry? | Urges resisted; delays achieved; estimated worry minutes falling |
| Activation (low mood) | Rate mood; pick one pleasure, one achievement and one value-linked activity for today at set times; predict enjoyment 0 to 10; rehearse the first two minutes | Done? Actual enjoyment and achievement? | Activities done; predicted against actual enjoyment; mood and PHQ-9 |
| Being enough (self-worth, self-love) | The old belief and the new one in the person's words, belief rated 0 to 100 weekly; collect one to three pieces of evidence from yesterday, said aloud; self-compassion for today's real difficulty; one act of self-respect | Evidence from today? Did the act of self-respect happen? | Evidence log count; belief in the old and new belief over weeks |
| Joy and positivity | Three good things from yesterday with "why it happened and my part"; plan one moment to savour; one kindness | Did you savour it? | Entries; savoured moments; mood |
| Letting go (rumination, regret, resentment) | Catch the loop; "is this helping me solve something?"; if yes, one concrete next step (how, not why); if not, unhook from the thought and turn to one valued action now; for resentment, steps towards acceptance or forgiveness over days | Caught and redirected how many times? | Times caught and redirected; "how stuck I feel" falling |
| Calm and sleep | Body scan, breathing, and a worry offload before sleep (write tomorrow's list), personalised | How was sleep? | Sleep ratings |

Interactive (with the therapist, by voice or text) is the main form. A listen-only version, filled in with the
person's own words from the app (their value, today's commitment, their kind phrase, their evidence), is there for
when they cannot talk.

## What this changes in the build

- Training data: the writer's practice guide (prompts/writer_practice.md) carries these programmes, role-play and
  first-person rehearsal; practice sessions in the series follow a programme day by day.
- Memory: an app-kept "Practice programmes" line in the memory block (programme, day, today's step, last prediction
  against outcome), so the model can run day 12 differently from day 1.
- Notes: a "Practice log" heading for commitments, predictions, outcomes and evidence, read by the app.
- App: a morning card and an evening debrief on Today, per-programme progress, listen-only personalised scripts.
