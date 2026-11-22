"""Summarise writer bake-off folders: per writer and mode, the automatic checks of every session (turn counts in
range, long turns, markdown, stock phrases, closing mood asked, safety question in intakes, plan items added and
rejected, notes with every heading), so the full read can focus on what the numbers cannot show.
Usage: python -I tests/bakeoff_report.py data/gen/bake_*
"""
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))
from formats import NOTE_HEADINGS  # noqa: E402

for d in sys.argv[1:]:
    files = sorted(Path(d).glob("series/*.json"))
    st = collections.Counter()
    kinds = collections.defaultdict(list)
    for f in files:
        r = json.loads(f.read_text())
        for s in r["sessions"]:
            k, c = s["spec"]["kind"], s["checks"]
            kinds[k].append(c["therapist_turns"])
            st["sessions"] += 1
            st["in_range"] += c["in_range"]
            st["turns_over_60_words"] += c["turns_over_60_words"]
            st["markdown"] += c["markdown"]
            st["stock_phrases"] += sum(c["stock_phrases"].values())
            note = s["training"]["note"][-1]["content"]
            st["note_all_headings"] += all(re.search(rf"^{re.escape(h)}\s*(\([^)]*\))?\s*:", note, re.M) for h in NOTE_HEADINGS)
            m = re.search(r"end\s*(\d+)\s*/\s*10", note)
            st["closing_mood_rated"] += bool(m) or k in ("written_exposure", "reliving")
            if k == "intake":
                st["intakes"] += 1
                st["intake_safety_asked"] += bool(re.search(r"suicid|not wanting to be here|harm(ing)? yourself|not want(ing)? to (live|wake)|"
                                                            r"end (your|their) life|safe", " ".join(t for w, t in s["turns"] if w == "therapist"), re.I))
            for x in s.get("plan_items", []):
                st["items_" + ("added" if x["added"] else "rejected")] += 1
            st["series_complete"] += 0
        st["series_complete"] += r.get("complete", False)
    print(f"== {Path(d).name}: {len(files)} series")
    print("   " + ", ".join(f"{k} {v}" for k, v in st.items()))
    print("   turns by kind: " + "; ".join(f"{k} {min(v)}-{max(v)} (mean {sum(v)/len(v):.1f})" for k, v in sorted(kinds.items())))
