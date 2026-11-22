"""The services the therapist offers (owner, 2026-11-07: CBT, ACT, DBT, coaching, ADHD, OCD, overthinking, anxiety,
letting go, loss, regret, and PLAN section 6), each with the words that show a person needs it. Used to measure
coverage (tests/service_coverage.py, docs/SERVICES.md), to seed new practice people for the gaps, and to give the
writer the playbook for the services a person needs (prompts/services/).

A service is what a person comes for (low mood, OCD, a career change); an approach (CBT, ACT, DBT, compassion-focused
work, motivational interviewing, behavioural activation, mindfulness, grounding) is how the therapist works, and each
service's playbook names the approaches that fit it.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Service:
    id: str
    name: str
    signs: str      # regex over what the person brings (concerns, goals, history, topic)
    methods: str    # regex over the writer's guides: the service's own methods, by name
    owner: bool     # named by the owner (2026-11-07 message or PLAN section 6)


SERVICES = [
    # mood and anxiety
    Service("depression", "Depression and low mood",
            r"depress|low mood|hopeless|empty inside|feel\w* (flat|numb|empty)|lost interest|no motivation|"
            r"can'?t get out of bed|postnatal|postpartum|after having a baby",
            r"behavioural activation|activation|pleasure and achievement|achievement and pleasure", True),
    Service("worry", "Anxiety and worry",
            r"\bworr|generali[sz]ed anxiety|\bGAD\b|what if|anxious all the time|constant\w* anxi|"
            r"(?<!social )(?<!health )anxiety",
            r"worry time|postpon\w* worry|uncertainty", True),
    Service("overthinking", "Overthinking, rumination and obsessive thinking",
            r"overthink|over-think|ruminat|replay|going over|can'?t stop thinking|stuck in (my|his|her|their) head|"
            r"second-guess|in circles|obsess\w* (about|over)|can'?t get (him|her|them|it|this|that) out of "
            r"(my|their|his|her) head",
            r"ruminat|how, not why|is this helping|postpon|detached mindfulness", True),
    Service("panic", "Panic", r"panic", r"panic", True),
    Service("social_anxiety", "Social anxiety",
            r"social anxiety|socially anxious|fear of being judged|public speaking|speaking up|embarrass|\bshy\b|"
            r"small talk",
            r"self-focus|attention outward|social anxiety", True),
    Service("health_anxiety", "Health anxiety (hypochondria)",
            r"health anxiety|(checking|googl\w*|search\w*) (my |their |his |her )?(body|(medical )?symptoms)|"
            r"symptoms? online|hypochondr|illness anxiety|GP for reassurance|fear of (having|getting) (a )?(serious )?"
            r"illness",
            r"health anxiety|checking (the|their) body", True),
    Service("fears", "Fears and phobias (fear ladders)",
            r"phobi|fear of (flying|needles|dogs|heights|driving|spiders|lifts|water|getting hurt)|afraid of|"
            r"scared of",
            r"ladder|exposure", True),
    Service("ocd", "OCD and obsessive thinking",
            # not "obsessing over" (rumination) and not reassurance alone (health and relationship worry seek it too)
            r"\bOCD\b|obsessive|intrusive|compuls(?!\w* (spend|shop|buy|gambl|eat|overeat))|ritual|checking (the |locks|doors|stove|oven)|wash\w* (my |their )?"
            r"hands|contaminat",
            r"response prevention|\bERP\b|compulsion|ritual|no reassurance", True),
    # addictive habits (owner, 2026-11-07: "healing from these addictions: overeating, gambling, ruminating and
    # obsessive thinking"; the last two are the overthinking and OCD services)
    Service("gambling", "Gambling and spending",
            r"gambl|betting|\bbets\b|sports? bet|casino|slot machines?|online slots|fruit machines?|scratch.?cards?|"
            r"lottery|poker|bookie|chasing (my |their |his |her )?loss|spending (addiction|problem|spree)|"
            r"addict\w* to (spending|shopping|buying)|compulsive (spending|shopping|buying)|shopping addiction|"
            r"overspend|can'?t stop (spending|shopping|buying)",
            r"self-exclu|gambling block|urge surf|chasing losses|thinking trap|debt advice", True),
    Service("overeating", "Overeating and binge eating",
            r"overeat|over-eat|binge.?eat|\bbing(e|es|eing|ing)\b(?!\W*(drink|watch))|comfort.?eat|emotional eating|"
            r"eat\w* in secret|secret eating|can'?t stop eating|food addiction|addict\w* to food|grazing|"
            r"lack of control (around|with|over) food|night eating|compulsive (eating|overeating)",
            r"regular eating|urge surf|self-monitor|food rules|forbidden food", True),    # attention and self-management
    Service("adhd", "ADHD skills",
            r"\bADHD\b|attention (deficit|difficult)|time blindness|distractib|easily distracted|forgetful|"
            r"lose track of time|hyperfocus|executive function",
            r"\bADHD\b|body doubl|sit with me", True),
    Service("focus", "Focus and procrastination",
            r"procrastinat|focus|concentrat|putting (things )?off|deadlines?",
            r"focus block|procrastinat|two minutes", True),
    Service("daydreaming", "Daydreaming", r"daydream|fantasy world|lost in (my |their )?(head|imagination)",
            r"daydream", True),
    Service("habits", "Habits", r"habit|routine|exercis|consisten", r"habit", True),
    Service("sleep", "Sleep", r"sleep|insomni", r"sleep|stimulus control|wind.down", False),
    # loss and the past
    Service("grief", "Loss and grief",
            r"grie[fv]|bereave|passed away|death of|\bdied\b|miscarriage|widow|loss of (my|their|his|her) "
            r"(mother|father|mum|dad|partner|wife|husband|son|daughter|child|friend|baby|pet|dog|cat)",
            r"grie[fv]|bereave", True),
    Service("regret", "Regret", r"regret|should have|shouldn'?t have|if only|missed (my|the|their) chance|wasted",
            r"regret", True),
    Service("letting_go", "Letting go (resentment, the past)",
            r"let(ting)? go|resent|grudge|forgiv|move on|moving on|can'?t get over|bitter",
            r"let(ting)? go|resent|forgiv", True),
    # self and others
    Service("being_enough", "Being enough (self-love, self-esteem, self-confidence, self-criticism, shame)",
            r"not (good )?enough|self-esteem|self esteem|self-love|love (my|them)sel|self-confiden|worthless|"
            r"self-worth|inadequa|impost[eo]r|\bfraud\b|"
            r"failure|self-critic|hate (my|them)sel|self-loathing|self-doubt|confidence|shame|guilt|perfectionis|"
            r"\blazy\b|a burden|incompetent|stupid",
            r"self-compassion|compassionate|self-critic", True),
    Service("relationships", "Relationships and attachment",
            r"relationship|attach|break-?up|divorce|marriage|boyfriend|girlfriend|husband|wife|dating|abandon|"
            r"people.pleas|boundar|conflict with",
            r"attachment|DEAR MAN|relationship", True),
    Service("emotions", "Feeling overwhelmed, strong emotions and impulses (DBT)",
            r"anger|angry|rage|temper|lash\w* out|self-harm|cutting|urges?\b|impuls|overwhelm|mood swings|"
            r"can'?t cope|everything is too much|falling apart|act\w* without thinking|snap\w* at",
            r"TIPP|opposite action|STOP|checking the facts|radical acceptance|ride the urge|pros and cons", True),
    Service("change", "Change and ambivalence (motivational interviewing)",
            r"drink|alcohol|smok|cannabis|cut down|quit\b|torn|ambivalen",  # gambling has its own service
            r"motivational interviewing|torn about", True),
    # growth and coaching
    Service("coaching", "Career and life coaching",
            r"career|promotion|change jobs|new job|unemploy|business|exam|study|returning to work|retire",
            r"coaching|career|WOOP", True),
    Service("wheel_of_life", "Wheel of life (balance)", r"balance|wheel of life|out of balance",
            r"wheel of life", True),
    Service("purpose", "Purpose and ikigai",
            r"purpose|meaning|ikigai|direction|what (I|they) want (to do )?with (my|their) life|calling|passion",
            r"ikigai|purpose", True),
    Service("higher_sense", "Higher sense (meaning, faith, spirit, on their terms)",
            r"spiritual|faith|\bgod\b|religio|something bigger|soul|connection to", r"spiritual|higher sense|faith",
            True),
    Service("joy", "Joy and doing what they love",
            r"\bjoy|\bfun\b|enjoy|happiness|hobb|creativ|doing what (I|they) love|playful",
            r"savour|three good things|joy", True),
    Service("trauma", "After something frightening (trauma; the gated reliving path)",
            r"trauma|PTSD|flashback|nightmare|bad dreams|jump\w* at|jumpy|spaced out|not actually .?there|"
            r"thousand_voices",
            r"reliving|written exposure|trauma", False),
    Service("health_conditions", "Living with illness or pain",
            r"chronic|\bpain\b|long-term illness|diagnosis|fatigue|brain fog|physical limitation",
            r"chronic|\bpain\b|pacing", False),
    Service("loneliness", "Loneliness", r"lonel|isolat|no friends", r"lonel", False),
    Service("stress", "Burnout and stress",
            r"burn\w*.?out|stress|overwork|exhaust|sick leave|can'?t switch off|dread\w* (work|monday)|cynical",
            r"burnout|recovery|stress", True),
]
BY_ID = {s.id: s for s in SERVICES}
# People wanted per service in the practice bank (2026-11-07): at least 40 for every service, 60 for ADHD and loss, and
# 100 for the four the owner named most important ("I need really good coverage on OCD, Depression, Purpose and
# Focus"); one person can bring several services.
PRIORITY = ("ocd", "depression", "purpose", "focus", "being_enough", "health_anxiety", "stress", "gambling",
            "overeating", "overthinking", "worry", "emotions")  # owner, 2026-11-07: "also make feeling overwhelmed,
# anxiety and managing impulse a priority as well"  # and "prioritise hypochondria
# as well. It is super relevant" (owner, 2026-11-07)  # "make sure self love, self esteem and self
# confidence is highly prioritised" (owner, 2026-11-07)
TARGET = {s.id: 100 if s.id in PRIORITY else 60 if s.id in ("adhd", "grief") else 40 for s in SERVICES}

# The approaches, named by the owner (PLAN section 6), and the words that show the writer's guides teach them. People
# do not bring an approach, so these are measured in the guides and later in the judged sessions, not in the people.
APPROACHES = {
    "CBT": r"thought record|weighing the evidence|decatastroph|behavioural experiment|problem solving",
    "ACT": r"defusion|willingness|drop anchor|committed action|workability",
    "DBT": r"TIPP|opposite action|STOP|checking the facts|DEAR MAN|radical acceptance",
    "Compassion-focused work": r"self-compassion|compassionate",
    "Motivational interviewing": r"motivational interviewing|their own reasons",
    "Behavioural activation": r"behavioural activation|valued activit",
    "Mindfulness and meditation": r"mindful|meditat",
    "Grounding": r"grounding|5-4-3-2-1|feet on the floor",
}
# Which fields of a practice person say what they bring. Not the history: a back-story that mentions a death or a
# job is not a person who comes for grief or a career (2026-11-07: grief 38 people with the history, 5 without).
FIELDS = ("presenting_concerns", "stated_goals", "source")


def person_text(profile: dict) -> str:
    parts = []
    for f in FIELDS:
        v = profile.get(f, "")
        parts.append(" ".join(v) if isinstance(v, list) else str(v))
    return " ".join(parts)


PLAYBOOKS = Path(__file__).resolve().parent.parent / "prompts" / "services"


def primary(profile: dict, n: int = 2) -> list[str]:
    """The person's main services, in the order they bring them (first concern first); an explicit list wins."""
    if profile.get("services"):
        return [s for s in profile["services"] if s in BY_ID][:n]
    order: list[str] = []
    for item in list(profile.get("presenting_concerns", [])) + list(profile.get("stated_goals", [])) + [
            str(profile.get("source", ""))]:
        order += [s.id for s in SERVICES if s.id not in order and re.search(s.signs, item, re.I)]
    return order[:n]


def playbooks(ids: list[str]) -> str:
    return "\n\n".join((PLAYBOOKS / f"{i}.md").read_text().strip() for i in ids)


def services_of(profile: dict) -> list[str]:
    """The services whose signs appear in what this person brings; an explicit 'services' list wins."""
    if profile.get("services"):
        return [s for s in profile["services"] if s in BY_ID]
    text = person_text(profile)
    return [s.id for s in SERVICES if re.search(s.signs, text, re.I)]
