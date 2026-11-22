"""Coverage of each service (pipeline/services.py; owner, 2026-11-07): how many practice people bring it, how often the
therapist writer's guides name its own methods, and how many probes test it. Gaps show before any writing is paid for.

  python3 -I tests/service_coverage.py PROFILES.jsonl [--markdown] [--kept SFT.jsonl]

With --kept (TASKLIST A12), it also counts the kept sessions per service in a combined training file (a session
counts once, however many rows it gave); the main writing run aims at 100 or more for every service.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
from services import APPROACHES, SERVICES, TARGET, services_of  # noqa: E402

# the therapist's guides only (writer_client.md and writer_profile.md write the person)
GUIDES = ["rulebook", "intake", "daily_checkin", "weekly_session", "practice", "planner", "bridge", "reliving",
          "written_exposure", "thinking"]
guide_text = " ".join((ROOT / "prompts" / f"writer_{g}.md").read_text() for g in GUIDES)
service_dir = ROOT / "prompts" / "services"
probes = [json.loads(l) for l in (ROOT / "tests" / "probes_v3.jsonl").read_text().splitlines() if l.strip()]
v4 = ROOT / "tests" / "probes_v4.jsonl"
probes += [json.loads(l) for l in v4.read_text().splitlines() if l.strip()] if v4.exists() else []
people = [json.loads(l) for l in Path(sys.argv[1]).read_text().splitlines() if l.strip()]

counts = {s.id: 0 for s in SERVICES}
for p in people:
    for s in services_of(p):
        counts[s] += 1
kept = None
if "--kept" in sys.argv:
    by_id = {p["id"]: services_of(p) for p in people}
    sessions = set()
    for line in Path(sys.argv[sys.argv.index("--kept") + 1]).read_text().splitlines():
        if line.strip():
            key = json.loads(line)["id"].split(":")[0]  # "p00012L#3:think1" -> "p00012L#3"
            sessions.add(key)
    kept = {s.id: 0 for s in SERVICES}
    for key in sessions:
        for s in by_id.get(key.split("#")[0].rstrip("LR"), []):
            kept[s] += 1


def probe_count(s) -> int:
    n = 0
    for p in probes:
        if p.get("service") == s.id:
            n += 1
        elif "service" not in p:
            said = " ".join(x for who, x in p["turns"] if who == "person")
            n += bool(re.search(s.signs, said, re.I))
    return n


rows = []
for s in SERVICES:
    rows.append({"id": s.id, "name": s.name, "owner": s.owner, "people": counts[s.id],
                 "share": counts[s.id] / len(people), "target": TARGET[s.id],
                 "gap": max(0, TARGET[s.id] - counts[s.id]), "guide_mentions": len(re.findall(s.methods, guide_text, re.I)),
                 "playbook": (service_dir / f"{s.id}.md").exists(), "probes": probe_count(s),
                 **({"kept_sessions": kept[s.id]} if kept else {})})
if "--markdown" in sys.argv:
    print("| Service | Owner named | People (of %d) | Target | Gap | Guide mentions of its methods | Playbook | Probes |"
          % len(people))
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['name']} | {'yes' if r['owner'] else 'added'} | {r['people']} ({r['share']:.0%}) | {r['target']} | {r['gap'] or ''} | "
              f"{r['guide_mentions']} | {'yes' if r['playbook'] else 'no'} | {r['probes']} |")
    print("\n| Approach | Guide mentions |\n|---|---|")
    for a, rx in APPROACHES.items():
        print(f"| {a} | {len(re.findall(rx, guide_text, re.I))} |")
    if kept:
        print("\n| Service | Kept sessions | 100 or more |\n|---|---|---|")
        for r in rows:
            print(f"| {r['name']} | {r['kept_sessions']} | {'yes' if r['kept_sessions'] >= 100 else 'NO'} |")
else:
    print(json.dumps(rows, indent=1))
none = sum(not services_of(p) for p in people)
print(f"\n{len(people)} people; {none} match no service", file=sys.stderr)
