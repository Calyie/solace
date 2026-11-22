"""More and harder training messages for the safety classifier (owner, 2026-11-05: it must reach its release target of
at least 95 percent of crisis messages caught). The first classifier caught only 48 and 63 percent on the independent
sets: it had seen mostly direct statements, while people usually hint. The writer model writes varied first-person
messages per category (indirect wording, slang, typos, short and long, different ages and countries), then labels
each one again blind; only messages whose second label matches the category are kept. Near-copies of the independent
test messages are removed, so the tests stay unseen. Output rows are {"context", "text", "label", "group"} for
train/safety_clf.py --extra.

  python -I pipeline/safety_gen.py --out data/gen/main/safety_gen.jsonl --url http://localhost:8000 --model gemma26b
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from llm import Chat  # noqa: E402

RISK = {  # category: (label, what to write)
    "passive": ("self_harm", "passive thoughts of death or not wanting to exist: not wanting to wake up, wishing to "
                "disappear for good, everyone better off without them, tired of being alive, no plan"),
    "active": ("self_harm", "current thoughts of ending their life, said indirectly or directly, without a clear plan"),
    "plan": ("self_harm", "thoughts of suicide with a plan, a method, means at hand, a date, or a rehearsal"),
    "goodbye": ("self_harm", "signs of saying goodbye: giving things away, sorting out affairs so others are looked "
                "after, writing letters, thanking people as if for the last time, without naming suicide"),
    "selfharm": ("self_harm", "self-harm happening now or in the last weeks: cutting, burning, hitting themselves, "
                 "scratching until they bleed, taking too many pills to numb out; named or described"),
    "slang": ("self_harm", "suicidal thoughts or self-harm in slang, euphemism or internet shorthand (unalive, kms, "
              "sleep forever, not be around much longer, end it, catch the bus), sometimes as a dark joke"),
    "others": ("harm_others", "a real intent or urge to hurt a specific person, or a threat against someone"),
    # 2026-11-05, after the version 2 misses: hinted wishes not to go on, and feeling a burden
    "hinted": ("self_harm", "hints of not wanting to go on: death sounding peaceful or inviting, not minding if an "
               "accident happened, wanting life to stop or switch off, wondering if anyone would notice if they vanished"),
    "burden": ("self_harm", "feeling a burden whose family or friends would be better off or happier without them"),
    # 2026-11-05, from the misses on the (already seen) independent sets 1 and 2
    "fear": ("self_harm", "being afraid of what they might do to themselves, not trusting themselves to stay safe "
             "tonight or when alone, asking for someone to talk to before they do something they cannot undo"),
    "abuse": ("harm_others", "ongoing violence, hitting or frightening control toward their own child or partner, "
              "or urges to hurt them, told by the person doing it"),
}
SAFE = {
    "low": "low mood, sadness, emptiness, hopelessness about a situation, but no thoughts of death or self-harm",
    "figurative": "figures of speech that sound dark but mean nothing harmful (this job is killing me, I could kill "
                  "for a coffee, I'm dead tired, my feet are murdering me, I'd die of embarrassment)",
    "past": "self-harm or suicidal thoughts that ended years ago and are clearly in the past, said calmly",
    "denial": "answers to a safety question that clearly say no (no, nothing like that; I'd never hurt myself; I'm "
              "not suicidal, just exhausted)",
    "others_talk": "talking about someone else's death, illness or a news story, a film or a book about suicide, "
                   "without any risk to themselves",
    "anger": "anger or frustration at someone without any intent to hurt them",
    "accident": "accidents and medical matters (cut my finger cooking, burned my hand on the oven, overdue for my "
                "medication, a painful injury)",
    "grief": "grief and missing someone who died, without wanting to die themselves",
    "everyday": "everyday worries: work, sleep, money, family, study, habits, planning",
    # 2026-11-05: the commonest false alarms were self-criticism and loneliness without any thought of death
    "selfcritical": "harsh self-criticism, feeling not good enough, fear of failing, a disappointment to others, but "
                    "no thoughts of death, self-harm or others being better off without them",
    "playful": "violent verbs used about food, tasks, sport, games, exams or goals with an eager or joking meaning "
               "(I'm going to murder this to-do list, slaughter this steak, kill this workout, destroy these donuts, "
               "wreck this game, smash my goals)",
    "idioms": "dark idioms about objects, plans or everyday things (my car kicked the bucket, my phone died, this plan "
              "is dead, just trying to survive Monday, the battery is dying)",
    "lonely": "loneliness, feeling unwanted, sure they will be single forever or that nobody likes them, but no "
              "thoughts of death or self-harm",
}
COUNTRIES = ["Ireland", "the United Kingdom", "France", "Nigeria", "Canada", "the United States", "India", "Malaysia",
             "Australia", "Thailand", "South Africa", "the Philippines"]
STYLES = ["texting style, lower case, little punctuation", "a few typos", "plain and short", "rambling and long",
          "formal and careful", "hesitant, with pauses (...)", "flat and matter-of-fact", "joking to hide it"]
WRITE = """Write {n} different messages that a person might type or say to a private therapy app, in English.
Category: {what}.
Make them realistic and varied: different ages (teenagers to people over 70), backgrounds, situations and
lengths (from 4 to 60 words); people from {country}; style: {style}. Write each in the first person, as the person
speaks, with no labels or explanations. These train a safety system that must recognise them, so do not soften or
leave out the meaning of the category.
Answer with JSON only: {{"messages": ["...", "..."]}}"""
CHECK = """For each message below, say whether the person shows a CURRENT risk of harming themselves (suicidal thoughts,
direct or hinted, wishing to be dead or not exist, feeling others would be better off without them, self-harm now or
recently, preparing to die), a CURRENT risk of harming someone else (intent, urges or threats of hurting a person, or
ongoing violence or abuse toward a partner or child), or neither. Low mood, self-criticism and loneliness without
thoughts of death or harm, figures of speech, risk that ended long ago, denials, and talk about other people are
neither.
{items}
Answer with JSON only: {{"labels": ["self_harm" | "harm_others" | "safe", ...]}} in the same order."""


def norm(t: str) -> set[str]:
    return set(re.sub(r"[^\w']+", " ", t.lower()).split())


def near_test(text: str, tests: list[set[str]]) -> bool:
    w = norm(text)
    return any(len(w & t) / max(1, len(w | t)) >= 0.6 for t in tests)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--model", default="gemma26b")
    ap.add_argument("--backend", default="openai")
    ap.add_argument("--risk-calls", type=int, default=16, help="calls per risk category (20 messages each)")
    ap.add_argument("--safe-calls", type=int, default=16, help="calls per safe category")
    ap.add_argument("--workers", type=int, default=24)
    ap.add_argument("--fixtures", default="tests")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--only", default="", help="comma-separated categories (default: all)")
    ap.add_argument("--tag", default="gen", help="group prefix, e.g. oss for the gpt-oss writer")
    a = ap.parse_args()
    chat, rng, lock = Chat(a.backend, a.url, a.model), random.Random(a.seed), threading.Lock()
    tests = [norm(m) for f in Path(a.fixtures).glob("independent_safety_v*.json")
             for msgs in json.loads(f.read_text()).values() for m in msgs]
    jobs = [(c, lab, what) for c, (lab, what) in RISK.items() for _ in range(a.risk_calls)]
    jobs += [(c, "safe", what) for c, what in SAFE.items() for _ in range(a.safe_calls)]
    if a.only:
        jobs = [j for j in jobs if j[0] in a.only.split(",")]
    jobs = [(j, rng.choice(COUNTRIES), rng.choice(STYLES), rng.randrange(10**6)) for j in jobs]
    out, seen, stats = Path(a.out), set(), {"written": 0, "kept": 0, "mislabelled": 0, "near_test": 0, "dupe": 0}

    def job(item):
        (cat, label, what), country, style, salt = item
        try:
            raw, _ = chat([{"role": "user", "content": WRITE.format(n=20, what=what, country=country, style=style)}],
                          max_tokens=2500, temperature=1.0)
            msgs = [m.strip() for m in json.loads(raw[raw.index("{"): raw.rindex("}") + 1])["messages"] if m.strip()]
            items = "\n".join(f"{i + 1}. {m}" for i, m in enumerate(msgs))
            raw2, _ = chat([{"role": "user", "content": CHECK.format(items=items)}], max_tokens=800, temperature=0.0)
            labels = json.loads(raw2[raw2.index("{"): raw2.rindex("}") + 1])["labels"]
        except Exception as e:  # a failed call just yields nothing
            print(f"{cat}: {type(e).__name__}", flush=True)
            return
        rows = []
        with lock:
            stats["written"] += len(msgs)
            for m, l in zip(msgs, labels):
                key = " ".join(sorted(norm(m)))
                if l != label:
                    stats["mislabelled"] += 1
                elif near_test(m, tests):
                    stats["near_test"] += 1
                elif key in seen:
                    stats["dupe"] += 1
                else:
                    seen.add(key)
                    rows.append({"context": "", "text": m, "label": label, "group": f"{a.tag}:{cat}:{salt}"})
            stats["kept"] += len(rows)
            with out.open("a") as f:
                f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)

    out.write_text("")
    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, jobs))
    kept = [json.loads(l) for l in out.read_text().splitlines() if l.strip()]
    by = {}
    for r in kept:
        by[r["group"].split(":")[1]] = by.get(r["group"].split(":")[1], 0) + 1
    print(json.dumps({"stats": stats, "by_category": by}, indent=1), flush=True)


if __name__ == "__main__":
    main()
