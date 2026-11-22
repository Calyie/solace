"""Plans, habits, goals, values and the vision board: kept by the app and built from the session notes.

After each session the app adds the items the note lists, but only those whose quote the person really said
(grounded), so nothing is added that they did not say. Between sessions the app keeps a day-by-day record and
notices patterns with fixed rules; the model is shown the result instead of having to work it out. The person can
change or remove any item in the app.

The Dart side (app/lib/core/plans.dart) must render, read and notice exactly the same; the app's tests compare it
with renderings made here (tests/make_app_fixtures.py).
"""
from __future__ import annotations

import datetime as dt
import random
import re
from dataclasses import asdict, dataclass, field

WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
PLAN_HEADINGS = ["Plan steps", "Habits", "Goals", "Values", "Vision board"]
MAX_NOTICED = 3


def label(d: dt.date) -> str:
    return f"{WEEKDAYS[d.weekday()]} {d.day} {d:%B}"


def norm(s: str) -> str:
    """Lower case, letters (accented ones too, for French and Igbo), digits and apostrophes only. The Dart side uses
    [^\\p{L}\\p{N}'] for the same thing."""
    return " ".join(re.sub(r"[^\w']|_", " ", s.lower().replace("’", "'")).split())


def grounded(quote: str, person_text: str) -> bool:
    """True when the quote (two words or more) is something the person said, ignoring case and punctuation. A quote
    shortened with "..." counts when every piece appears in what they said, in order."""
    pieces = [norm(x) for x in re.split(r"\.\.\.|…", quote)]
    pieces = [x for x in pieces if x]
    if sum(len(x.split()) for x in pieces) < 2:
        return False
    said, at = norm(person_text), 0
    for x in pieces:
        i = said.find(x, at)
        if i < 0:
            return False
        at = i + len(x)
    return True


def clean_note(note: str, person_text: str) -> tuple[str, list[str]]:
    """The note with every plan item whose quote the person never said taken out (a heading left empty says
    "none"), and the lines taken out. Training notes are cleaned this way, so the model learns notes the app keeps
    whole."""
    pattern = re.compile(r"^\s*(" + "|".join(re.escape(h) for h in PLAN_HEADINGS) + r")\s*(?:\([^)]*\))?\s*:[ \t]*", re.M)
    from formats import NOTE_HEADINGS  # noqa: E402 (formats imports plans lazily, so this is safe)
    any_heading = re.compile(r"^\s*(" + "|".join(re.escape(h) for h in NOTE_HEADINGS) + r")\s*(?:\([^)]*\))?\s*:", re.M)
    out, dropped, pos = [], [], 0
    for m in pattern.finditer(note):
        nxt = any_heading.search(note, m.end())
        end = nxt.start() if nxt else len(note)
        body = note[m.end():end]
        kept = []
        for line in body.split("\n"):
            rows = parse_items(line)
            if rows and not grounded(rows[0].get("they said", ""), person_text):
                dropped.append(line.strip())
            elif line.strip():
                kept.append(line.strip())
        out.append(note[pos:m.end()])
        out.append("\n".join(kept) if kept and any(parse_items(k) for k in kept) else "none")
        out.append("\n" if nxt else "")
        pos = end
    out.append(note[pos:])
    return "".join(out), dropped


@dataclass
class Step:
    text: str
    day: str = ""      # ISO date, or "" for some time this week
    time: str = ""     # "10:00", or ""
    ifthen: str = ""
    quote: str = ""
    added: str = ""
    status: str = "open"  # open, done or dropped
    moves: int = 0


@dataclass
class Habit:
    text: str
    cue: str = ""
    tiny: str = ""
    quote: str = ""
    start: str = ""
    kept: list[str] = field(default_factory=list)    # ISO dates
    missed: list[str] = field(default_factory=list)  # ISO dates


@dataclass
class Goal:
    text: str
    next_step: str = ""
    quote: str = ""
    added: str = ""
    last_progress: str = ""


@dataclass
class Value:
    text: str
    quote: str = ""
    added: str = ""


@dataclass
class Picture:
    title: str
    wish: str = ""
    outcome: str = ""
    obstacle: str = ""
    plan: str = ""
    quote: str = ""
    added: str = ""
    last_action: str = ""


CUE_WORDS = ("after ", "before ", "when ", "at ", "on ", "every ", "once ", "as soon as ")


def cue_text(cue: str) -> str:
    """'coffee' -> 'after coffee'; a cue that already says when ('after coffee', 'when I wake') stays as it is."""
    return "" if not cue else cue if cue.lower().startswith(CUE_WORDS) else f"after {cue}"


def _d(iso: str) -> dt.date:
    return dt.date.fromisoformat(iso)


@dataclass
class Plans:
    steps: list[Step] = field(default_factory=list)
    habits: list[Habit] = field(default_factory=list)
    goals: list[Goal] = field(default_factory=list)
    values: list[Value] = field(default_factory=list)
    pictures: list[Picture] = field(default_factory=list)

    @classmethod
    def from_dict(cls, d: dict) -> "Plans":
        return cls(steps=[Step(**x) for x in d.get("steps", [])], habits=[Habit(**x) for x in d.get("habits", [])],
                   goals=[Goal(**x) for x in d.get("goals", [])], values=[Value(**x) for x in d.get("values", [])],
                   pictures=[Picture(**x) for x in d.get("pictures", [])])

    def to_dict(self) -> dict:
        return asdict(self)

    # ---- what the model is shown ----
    def as_text(self, today: dt.date) -> str:
        t = today.isoformat()

        def step(s: Step, with_day: bool) -> str:
            when = " ".join(x for x in ((label(_d(s.day)) if with_day and s.day else ""), s.time) if x)
            out = (when + " " if when else "") + s.text
            if s.ifthen:
                out += f" ({s.ifthen})"
            if s.status == "done":
                out += ", done"
            if s.moves:
                out += f", moved {s.moves} time{'s' if s.moves > 1 else ''}"
            return out

        by_time = lambda s: (s.time or "99:99", s.text)  # noqa: E731
        today_steps = sorted([s for s in self.steps if s.day == t and s.status != "dropped"], key=by_time)
        coming = sorted([s for s in self.steps if s.day > t and s.status == "open"], key=lambda s: (s.day, *by_time(s)))
        missed = sorted([s for s in self.steps if s.day and s.day < t and s.status == "open"], key=lambda s: s.day)
        anytime = [s for s in self.steps if not s.day and s.status == "open"]
        week_ago = (today - dt.timedelta(days=7)).isoformat()
        done_recent = sorted([s for s in self.steps if s.day and week_ago <= s.day < t and s.status == "done"],
                             key=lambda s: s.day)

        def habit(h: Habit) -> str:
            days = [(today - dt.timedelta(days=k)).isoformat() for k in range(7, 0, -1)]
            marks = ["yes" if d in h.kept else "no" if d in h.missed else "-" for d in days]
            n_kept, n_known = marks.count("yes"), sum(m != "-" for m in marks)
            extra = "; ".join(x for x in (cue_text(h.cue), (f"tiny version: {h.tiny}" if h.tiny else "")) if x)
            out = h.text + (f" ({extra})" if extra else "")
            out += f": kept {n_kept} of {n_known} days in the last week" if n_known else ": new"
            return out + (f" ({', '.join(marks)})" if n_known else "")

        def goal(g: Goal) -> str:
            out = g.text + (f", next step: {g.next_step}" if g.next_step else "")
            return out + (f", last progress {label(_d(g.last_progress))}" if g.last_progress else "")

        def picture(p: Picture) -> str:
            return p.title + (f" (plan: {p.plan})" if p.plan else "")

        # (name, items, shown even when empty)
        rows = [
            ("Today's plan", [step(s, False) for s in today_steps], True),
            ("Done in the last 7 days", [step(s, True) for s in done_recent[-5:]], False),
            ("Coming up", [step(s, True) for s in coming[:4]], False),
            ("Missed and not re-planned", [step(s, True) for s in missed[-3:]], False),
            ("This week, no day set", [step(s, False) for s in anytime[:3]], False),
            ("Habits", [habit(h) for h in self.habits], True),
            ("Goals", [goal(g) for g in self.goals], True),
            ("Values", [v.text for v in self.values], True),
            ("Vision board", [picture(p) for p in self.pictures], True),
            ("Noticed by the app", self.noticed(today), True),
        ]
        return "Plans kept by the app (the person can change them):\n" + "\n".join(
            f"{name}: {'; '.join(items) if items else 'none'}" for name, items, always in rows if items or always)

    # ---- fixed rules, in priority order ----
    def noticed(self, today: dt.date) -> list[str]:
        out = []
        for s in self.steps:
            if s.status == "open" and s.moves >= 3:
                out.append(f"\"{s.text}\" has been moved {s.moves} times")
        for h in self.habits:
            fired = False
            for wd in range(7):
                last_two = [today - dt.timedelta(days=k) for k in range(1, 15) if (today - dt.timedelta(days=k)).weekday() == wd]
                if all(d.isoformat() in h.missed for d in last_two):
                    out.append(f"{h.text} was missed on the last two {WEEKDAYS[wd]}s")
                    fired = True
                    break
            if not fired and (today - dt.timedelta(days=1)).isoformat() in h.missed:
                out.append(f"{h.text} was missed yesterday")
        for g in self.goals:
            if g.last_progress and (today - _d(g.last_progress)).days >= 14:
                out.append(f"goal \"{g.text}\": no progress in {(today - _d(g.last_progress)).days} days")
        for h in self.habits:
            n = sum((today - dt.timedelta(days=k)).isoformat() in h.kept for k in range(1, 15))
            if h.start and (today - _d(h.start)).days >= 14 and n >= 12:
                out.append(f"{h.text} was kept on {n} of the last 14 days")
        for p in self.pictures:
            ref = p.last_action or p.added
            if ref and (today - _d(ref)).days >= 30:
                out.append(f"vision board \"{p.title}\": nothing done in {(today - _d(ref)).days} days")
        return out[:MAX_NOTICED]

    # ---- built from the note ----
    def apply_note(self, sections: dict[str, str], today: dt.date, person_text: str) -> list[dict]:
        """Add the items in a note's plan headings. Returns every item with whether it was added and why not."""
        log = []
        for heading in PLAN_HEADINGS:
            for row in parse_items(sections.get(heading, "")):
                kind, item = row["kind"], row["item"]
                quote = row.get("they said", "")
                has_item = bool(item) and (kind != "when" or bool(row.get("step")))
                ok = has_item and grounded(quote, person_text)
                log.append({"heading": heading, "kind": kind, "item": item, "quote": quote, "added": ok,
                            "why": "" if ok else ("no item" if not has_item else "quote not found in what they said")})
                if not ok:
                    continue
                iso = today.isoformat()
                if kind == "when":
                    day, time = parse_when(item, today)
                    text = row.get("step", "")
                    again = next((x for x in self.steps if x.status == "open" and norm(x.text) == norm(text)), None)
                    if again is None:
                        self.steps.append(Step(text=text, day=day, time=time, ifthen=row.get("if-then", ""),
                                               quote=quote, added=iso))
                    else:  # the same open step planned again counts as moved, not as a second step
                        again.day, again.time, again.moves = day, time, again.moves + 1
                        again.ifthen = row.get("if-then", again.ifthen)
                elif kind == "habit":
                    h = next((x for x in self.habits if norm(x.text) == norm(item)), None)
                    if h is None:
                        self.habits.append(Habit(text=item, cue=row.get("cue", ""), tiny=row.get("tiny version", ""),
                                                 quote=quote, start=iso))
                    else:
                        h.cue, h.tiny = row.get("cue", h.cue), row.get("tiny version", h.tiny)
                elif kind == "goal":
                    g = next((x for x in self.goals if norm(x.text) == norm(item)), None)
                    if g is None:
                        self.goals.append(Goal(text=item, next_step=row.get("next step", ""), quote=quote, added=iso,
                                               last_progress=iso))
                    elif row.get("next step") and norm(row["next step"]) != norm(g.next_step):
                        g.next_step, g.last_progress = row["next step"], iso
                elif kind == "value":
                    if not any(norm(v.text) == norm(item) for v in self.values):
                        self.values.append(Value(text=item, quote=quote, added=iso))
                elif kind == "picture":
                    p = next((x for x in self.pictures if norm(x.title) == norm(item)), None)
                    fields = {k: row.get(k, "") for k in ("wish", "outcome", "obstacle", "plan")}
                    if p is None:
                        self.pictures.append(Picture(title=item, quote=quote, added=iso, **fields))
                    else:
                        for k, v in fields.items():
                            if v:
                                setattr(p, k, v)
        return log


ITEM_KINDS = {"when", "habit", "goal", "value", "picture"}


def parse_items(text: str) -> list[dict]:
    """'kind: item | key: value | they said: "words"' lines -> dicts; 'none' and other lines are skipped."""
    out = []
    for raw in text.split("\n"):
        parts = [p.strip() for p in raw.strip().lstrip("-*• ").split("|")]
        head = re.match(r"^(when|habit|goal|value|picture)\s*:\s*(.*)$", parts[0], re.I)
        if not head:
            continue
        row = {"kind": head.group(1).lower(), "item": head.group(2).strip().strip('"').strip()}
        for p in parts[1:]:
            k, _, v = p.partition(":")
            if k.strip() and v.strip():
                row[k.strip().lower()] = v.strip()
        if "they said" in row:
            row["they said"] = row["they said"].strip().strip('"“”').strip()
        out.append(row)
    return out


def parse_when(text: str, today: dt.date) -> tuple[str, str]:
    """'today 10:00', 'tomorrow', 'Wednesday 18:30', 'this week' -> (ISO day or "", "HH:MM" or "")."""
    low = text.lower()
    m = re.search(r"\b(\d{1,2})[:.h](\d{2})\b", low)
    time = f"{int(m.group(1)):02d}:{m.group(2)}" if m and int(m.group(1)) < 24 and int(m.group(2)) < 60 else ""
    if "today" in low or "tonight" in low:
        return today.isoformat(), time
    if "tomorrow" in low:
        return (today + dt.timedelta(days=1)).isoformat(), time
    for i, name in enumerate(WEEKDAYS):
        if name.lower() in low:
            ahead = (i - today.weekday()) % 7 or 7
            return (today + dt.timedelta(days=ahead)).isoformat(), time
    return "", time


def simulate_days(plans: Plans, start: dt.date, end: dt.date, p_keep, rng: random.Random) -> None:
    """Stand-in for the person living the days between two sessions (training data only): habits kept or missed
    (each habit has one weaker weekday, so patterns appear), planned steps done, moved or missed, goals and pictures
    moving now and then. p_keep(date) gives the chance of following through that day."""
    d = start
    while d < end:
        p, iso = p_keep(d), d.isoformat()
        for h in plans.habits:
            if h.start and h.start <= iso:
                weak = sum(map(ord, h.text)) % 7
                keep = rng.random() < (p * 0.35 if d.weekday() == weak else p)
                (h.kept if keep else h.missed).append(iso)
        for s in plans.steps:
            if s.status == "open" and s.day == iso:
                if rng.random() < p:
                    s.status = "done"
                elif rng.random() < 0.6:
                    s.day, s.moves = (d + dt.timedelta(days=rng.choice([1, 2]))).isoformat(), s.moves + 1
        for g in plans.goals:
            if rng.random() < p * 0.12:
                g.last_progress = iso
        for pic in plans.pictures:
            if rng.random() < p * 0.06:
                pic.last_action = iso
        d += dt.timedelta(days=1)
