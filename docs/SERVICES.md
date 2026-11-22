# The services: what the therapist must do as well as an expert

Owner, 2026-11-07: the therapy must be better than a typical therapist's and on a par with advanced, research-backed
therapists and coaches, in every service the owner asked for (their message of 2026-11-07 and PLAN section 6). This
page is the map (TASKLIST A1): each service, what people bring, what an expert does, and how well the training data
covers it today. The playbooks with sources (A2) go in prompts/services/, one file per service, and the writer reads
the playbooks for the services each person brings.

A service is what a person comes for. An approach (CBT, ACT, DBT, compassion-focused work, motivational interviewing,
behavioural activation, mindfulness, grounding) is how the therapist works; each playbook names the approaches that
fit its service. The services and the words that show a person needs one are in pipeline/services.py.

## Coverage today (2026-11-07)

Measured by `python3 -I tests/service_coverage.py PROFILES.jsonl --markdown` on the 596 practice people of round 1.
"People" counts only what each person brings (their concerns, goals and topic), not their back-story: with the
back-story, grief showed 38 people, but only 5 come for it. One person can bring several services. "Guide mentions"
counts how often the therapist writer's guides name the service's own methods. "Probes" counts the probes whose
person turns mention the service (an approximate count until the service probes, A4, carry a service label).

| Service | Owner named | People (of 596) | Target | Gap | Guide mentions of its methods | Playbook | Probes |
|---|---|---|---|---|---|---|---|
| Depression and low mood | yes | 31 (5%) | 60 | 29 | 3 | no | 2 |
| Anxiety and worry | yes | 184 (31%) | 40 |  | 3 | no | 1 |
| Overthinking and rumination | yes | 54 (9%) | 40 |  | 2 | no | 0 |
| Panic | yes | 50 (8%) | 40 |  | 2 | no | 3 |
| Social anxiety | yes | 29 (5%) | 40 | 11 | 0 | no | 1 |
| Health anxiety | yes | 5 (1%) | 40 | 35 | 0 | no | 1 |
| Fears and phobias (fear ladders) | yes | 12 (2%) | 40 | 28 | 8 | no | 0 |
| OCD and obsessive thinking | yes | 29 (5%) | 40 | 11 | 2 | no | 0 |
| ADHD skills | yes | 9 (2%) | 60 | 51 | 3 | no | 1 |
| Focus and procrastination | yes | 96 (16%) | 40 |  | 4 | no | 3 |
| Daydreaming | yes | 6 (1%) | 40 | 34 | 0 | no | 1 |
| Habits | yes | 36 (6%) | 40 | 4 | 13 | no | 4 |
| Sleep | added | 168 (28%) | 40 |  | 8 | no | 9 |
| Loss and grief | yes | 5 (1%) | 60 | 55 | 1 | no | 5 |
| Regret | yes | 11 (2%) | 40 | 29 | 1 | no | 0 |
| Letting go (resentment, the past) | yes | 22 (4%) | 40 | 18 | 10 | no | 2 |
| Being enough (self-worth, self-criticism, shame) | yes | 237 (40%) | 40 |  | 6 | no | 0 |
| Relationships and attachment | yes | 113 (19%) | 40 |  | 2 | no | 0 |
| Strong emotions and urges (DBT) | yes | 34 (6%) | 40 | 6 | 13 | no | 4 |
| Change and ambivalence (motivational interviewing) | yes | 20 (3%) | 40 | 20 | 3 | no | 4 |
| Career and life coaching | yes | 74 (12%) | 40 |  | 5 | no | 3 |
| Wheel of life (balance) | yes | 11 (2%) | 40 | 29 | 2 | no | 1 |
| Purpose and ikigai | yes | 45 (8%) | 40 |  | 5 | no | 1 |
| Higher sense (meaning, faith, spirit, on their terms) | yes | 4 (1%) | 40 | 36 | 2 | no | 1 |
| Joy and doing what they love | yes | 67 (11%) | 40 |  | 7 | no | 1 |
| After something frightening (trauma; the gated reliving path) | added | 101 (17%) | 40 |  | 6 | no | 2 |
| Living with illness or pain | added | 47 (8%) | 40 |  | 0 | no | 0 |
| Loneliness | added | 43 (7%) | 40 |  | 0 | no | 1 |
| Stress and burnout | added | 138 (23%) | 40 |  | 10 | no | 0 |

| Approach | Guide mentions |
|---|---|
| CBT | 5 |
| ACT | 5 |
| DBT | 14 |
| Compassion-focused work | 5 |
| Motivational interviewing | 2 |
| Behavioural activation | 2 |
| Mindfulness and meditation | 5 |
| Grounding | 7 |

What this shows:
- Five services the owner named have almost no people: loss and grief (5), health anxiety (5), higher sense (4),
  daydreaming (6) and ADHD (9). Regret, wheel of life, fears, motivational interviewing and letting go are thin.
  The total gap is about 400 people (A3).
- The writer's guides teach each service in one line at most ("Choosing methods" in prompts/writer_rulebook.md).
  Social anxiety, health anxiety, daydreaming, illness and loneliness have no method named at all; OCD is taught as
  "postponing worry, no reassurance", without exposure and response prevention; grief and regret are never taught.
  A typical therapist knows the general skills the rulebook teaches well; what makes an expert is the
  service-specific method, and that is the gap the playbooks (A2) close.
- Eight services have no probe (overthinking, fears, OCD, regret, being enough, relationships, illness, stress),
  so the tests could not see whether the model handles them (A4).

## What an expert does, service by service

The methods below are the ones the research supports for each service (the wheel of life is the exception: a
coaching tool with no trial behind it; docs/SERVICE_SOURCES.md). A2 writes each one out for the writer, step
by step, with what an average therapist gets wrong and when to point the person to other help, with at least two
checked sources each. Nothing here is a diagnosis: the therapist works on what the person brings, in their words.

**Depression and low mood.** People bring: no energy, nothing feels good, staying in bed, cutting off, hopelessness.
Expert: behavioural activation (action by plan, not by mood; small valued activities scheduled and reviewed; the
avoidance loop mapped together), cognitive work once there is some energy, rumination as a target, progress tracked
by questionnaire. Points elsewhere: any risk, very high or rising scores, no change after several weeks.

**Anxiety and worry.** People bring: constant "what if", anxiety most of the day for years, tension, reassurance,
trouble switching off. Expert: the worry cycle from their own example, real problems sorted from "what ifs", problem
solving, worry postponement, beliefs that worry helps or cannot be controlled tested, living with uncertainty step by
step, reassurance cut down, applied relaxation, avoidance faced on a ladder; panic, social, health and OCD fears go
to their own playbooks.

**Overthinking, rumination and obsessive thinking.** People bring: going over the past, replaying conversations,
"why me", thinking about an ex or a mistake for hours, a mind that will not switch off. Expert: rumination as a
mental habit set off by cues (function and triggers found), "is this helping", abstract "why" turned to concrete
"how", if-then plans for the cues, a postponed thinking time, detached mindfulness and attention training,
absorbing activity, compassion; intrusive thoughts with rituals go to the OCD playbook.

**Gambling and spending.** People bring: gambling or compulsive buying they cannot stop, chasing losses, hidden
debts, shame. Expert: what it gives them and their triggers, their own reasons (motivational interviewing), barriers
first (self-exclusion, bank gambling blocks, apps deleted), urge surfing, the gambling thinking traps checked against
their own record, a chain from a recent episode, the evenings refilled, the money faced with debt advice, relapse
prevention. Points elsewhere: debt advice, gambling support services, and suicide risk when debts or a relapse hit.

**Overeating and binge eating.** People bring: bingeing, eating in secret or at night, comfort eating, feeling
addicted to food, the diet and binge cycle. Expert: guided CBT self-help for binge eating (self-monitoring without
calories, regular eating, urge surfing, feelings met another way, food rules loosened, self-compassion after a binge),
never diet advice or weight targets. Points elsewhere: purging, fasting or other compensating, very low weight,
health conditions affected by food.

**Panic.** People bring: attacks, fear of the next one, avoiding places, escape plans. Expert: the panic cycle drawn
from their own attack (body sensation, catastrophic reading, more fear), dropping safety behaviours, bringing on the
sensations on purpose to learn they are safe, testing the feared outcome.

**Social anxiety.** People bring: fear of being judged, rehearsing, hiding, replaying afterwards. Expert: attention
turned outward, dropping safety behaviours as an experiment and comparing, testing how they actually come across,
stopping the post-mortem replay.

**Health anxiety.** People bring: checking the body, searching symptoms, seeking reassurance from doctors.
Expert: two explanations weighed (a serious illness, or a worry problem that makes normal sensations feel
dangerous), checking and reassurance cut down step by step, attention to the body tested; medical checks left to
their doctor.

**Fears and phobias.** People bring: avoiding flying, needles, dogs, driving, water. Expert: a ladder they build,
exposure aimed at learning that the feared outcome does not happen (expectations named before, compared after),
varied practice, safety behaviours dropped.

**OCD and obsessive thinking.** People bring: intrusive thoughts, checking, washing, mental rituals, reassurance.
Expert: exposure and response prevention, built with them and graded; the role of responsibility and of trying not
to think; no reassurance, explained kindly; the many forms of OCD recognised (harm, relationship, contamination,
symmetry, purely mental). Points elsewhere: severe or long-standing OCD, for specialist help alongside.

**ADHD skills.** People bring: time blindness, unfinished tasks, forgetting, overwhelm, shame. Expert: the skills of
CBT for adult ADHD (one calendar and one task list, tasks split small, distractions planned for, time made visible,
unhelpful thoughts about themselves worked on), structure built outside the head, never a diagnosis. Points
elsewhere: a suggested assessment when they ask about diagnosis or medication.

**Focus and procrastination.** People bring: putting things off, deadlines, guilt. Expert: the avoided feeling found
(what the task makes them feel), the first step made tiny, if-then plans, self-forgiveness for past delay (which
predicts less delay later).

**Daydreaming.** People bring: hours lost in vivid inner stories, often with music or pacing, hiding it. Expert:
curiosity first (what the daydreams give them), triggers tracked, the needs met in real life where possible, urges
delayed and redirected, never shaming; ordinary daydreaming is healthy and is not treated as a problem.

**Habits.** People bring: failed attempts, all or nothing. Expert: tiny habits tied to an existing cue, the
environment changed, repetition in the same context, never miss twice, realistic timelines (weeks to months).

**Sleep.** People bring: lying awake, waking early, dreading bedtime. Expert: the methods of CBT for insomnia (bed
for sleep only, getting up when awake, a regular rising time, worry dealt with before bed); sleep hygiene alone is
not enough. Points elsewhere: snoring and pauses in breathing, or sleep restriction when there is bipolar disorder or
epilepsy, with their doctor.

**Loss and grief.** People bring: the death of a parent, partner, child, friend or pet; pregnancy loss; loss after a
divorce. Expert: grief as love with nowhere to go, not a problem to fix; moving between grieving and getting on with
life; keeping a bond with the person who died; meaning made slowly; no "stages". Points elsewhere: grief that stays
intense and disabling for a long time (prolonged grief), or risk.

**Regret.** People bring: a choice they wish they had made, years they feel wasted. Expert: what can still be
repaired is repaired; what cannot is held with self-compassion, which research links to learning from regret rather
than drowning in it; useful "if only" thinking (a lesson for next time) told apart from rumination.

**Letting go.** People bring: resentment, a betrayal, the past replaying. Expert: forgiveness work for those who want
it (forgiving is not excusing, forgetting or reconciling), acceptance of what cannot change, unhooking from the loop
and turning to what matters now.

**Being enough.** People bring: self-criticism, shame, perfectionism, "not good enough". Expert: compassion-focused
work (the inner critic understood as a threat response, a kinder inner voice built and practised), the old belief
and a new one weighed with evidence collected day by day, perfectionism's costs tested.

**Relationships and attachment.** People bring: anxious or avoidant patterns, breakups, conflict, people-pleasing,
boundaries. Expert: their attachment pattern understood with compassion, needs asked for clearly (DEAR MAN), soft
starts and repair after conflict, boundaries set and kept, never taking sides against someone who is not there.

**Feeling overwhelmed, strong emotions and impulses.** People bring: everything too much, emotional storms,
anger, impulses they regret (spending, eating, messages, outbursts), urges to self-harm. Expert: DBT skills (chain
analysis, STOP, TIPP, riding the urge, pros and cons, checking the facts, opposite action, radical acceptance), a
delay rule and making impulses harder, and for practical overwhelm everything onto paper, sorted, one next step and
help asked for; self-harm always gets the safety response.

**Change and ambivalence.** People bring: drinking, smoking, cannabis, a change they feel torn about. Expert:
motivational interviewing (their own reasons for change drawn out and strengthened, never argued, the decision
theirs). Points elsewhere: stopping heavy drinking suddenly (medical help).

**Career and life coaching.** People bring: direction, a career change, burnout, returning to work. Expert: the goal
made clear, reality explored, options generated, a committed step (GROW); strengths and values; small experiments
with a new path before big leaps; their job reshaped where possible.

**Wheel of life.** People bring: feeling out of balance. Expert: their own life areas, rated for satisfaction, one
area chosen, one step, re-rated monthly; never a fixed template.

**Purpose and ikigai.** People bring: "what am I for", emptiness despite success. Expert: ikigai as the Japanese
idea of what makes life worth living, often small and daily (the four-circle diagram is a later Western blend);
values, a best possible future self, meaning found in action.

**Higher sense.** People bring: faith, spiritual searching, a wish for connection to something bigger. Expert: their
own beliefs followed with respect, spiritual struggles taken seriously, awe and connection explored on their terms;
never a belief pushed.

**Joy and doing what they love.** People bring: life that is all duty, forgotten hobbies. Expert: positive
psychology exercises that research supports (three good things, savouring, using their strengths), joy scheduled as
seriously as work, flow.

**After something frightening (trauma).** The existing gated reliving and written-exposure path (prompts/
writer_reliving.md, writer_written_exposure.md); unchanged here.

**Living with illness or pain.** People bring: pain, fatigue, a lost role, being a burden. Expert: acceptance and
values (ACT for chronic pain), pacing, identity rebuilt; medical questions left to their doctor.

**Loneliness.** People bring: few friends, a move, feeling unseen. Expert: the thoughts that keep people away worked
on (research finds this works best), small social steps, connection rebuilt.

**Burnout and stress.** People bring: exhaustion that rest no longer fixes, cynicism about work, feeling useless,
dread, sick leave, carers with no break. Expert: the WHO's three parts of burnout found, recovery first (detaching,
rest, mastery, control), the demands and mismatches sorted, limits rehearsed, values and reshaping the job, a gradual
return from sick leave; points to their doctor when it looks like depression or rest does not help.
