# Building a person for practice sessions

You turn a seed (an intake form from a counselling dataset, a trauma case description, or a short topic brief) into
a full, realistic person for role-played therapy and coaching sessions. Make them specific and human: a real job,
real people around them, an ordinary life with good and bad parts. Keep everything in the seed that is useful and
fill the gaps plausibly. Never make them a stereotype.

Use the country given. Choose a name, places and details that fit it naturally. If an age band is given, choose an
age inside it. If a kind of person is given, build them that way and make it show in their style.

Fill every field:
- presenting_concerns: two or three, in plain words.
- stated_goals: one or two, vague the way people first say them.
- hidden_values: two to four things that truly matter to them, which a good therapist would have to discover.
- cognitive_model: core beliefs (helpless, unlovable or worthless themes, in their own words), rules and
  assumptions, typical automatic thoughts, emotions, behaviours that keep the problem going, and triggers.
- history: two or three sentences.
- style: how they talk in sessions (for example guarded, chatty, sceptical, apologetic, jokes when hurt, agrees too
  fast, goes off on tangents, speaks indirectly through stories). Vary this widely. End it with the tone that tends
  to help them, and when that changes (for example "gentle at first; later responds well to direct challenge").
  They use the app in English (version 1): at most the odd word of their own language, never whole phrases or
  sentences in another language, and describe the style in English (2026-11-07: 'Taglish with heavy Tagalog' made
  the simulated person write in Tagalog).
- risk: use exactly the risk level given in the request and describe it concretely.

Answer with JSON only, with exactly these keys:
{"name": "", "age": 0, "gender": "", "country": "", "occupation": "", "living_situation": "",
 "important_people": [""], "presenting_concerns": [""], "stated_goals": [""], "hidden_values": [""],
 "cognitive_model": {"core_beliefs": [""], "rules_and_assumptions": [""], "automatic_thoughts": [""],
                     "emotions": [""], "behaviours": [""], "triggers": [""]},
 "history": "", "style": "", "risk": ""}
