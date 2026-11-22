"""Run the data pipeline at scale on the pod: generate series in parallel, judge them one judge model at a time,
then combine the verdicts into the training set. Every step is resumable: finished work is skipped on rerun.

  python -I batch.py generate --profiles P.jsonl --out-dir D --url U --model M --workers 48 [--duet] [--limit N]
  python -I batch.py judge    --out-dir D --profiles P.jsonl --judge-name NAME --url U --model M --workers 48
  python -I batch.py combine  --out-dir D --judges a,b,c

combine keeps a session only if every judge passes it; within a series it stops at the first note that fails,
because every later session was built on that note's memory.
"""
from __future__ import annotations

import argparse
import collections
import json
import time
import random
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import formats  # noqa: E402
from formats import ClientProfile  # noqa: E402
from llm import Chat, anthropic_spent  # noqa: E402
import judge  # noqa: E402
import series  # noqa: E402
import simulate  # noqa: E402


def load_profiles(path: str) -> dict[str, ClientProfile]:
    out = {}
    for line in Path(path).read_text().splitlines():
        if line.strip():
            p = ClientProfile.from_dict(json.loads(line))
            out[p.id] = p
    return out


def generate(a) -> None:
    # 2026-11-05: a WAIT file in the output folder holds the run until it is removed (the owner asked for research on
    # therapist qualities to go into the rulebook before the natural-length conversations are written)
    gate = Path(a.out_dir) / "WAIT"
    if gate.exists():
        print("waiting: remove " + str(gate) + " to start", flush=True)
    while gate.exists():
        time.sleep(30)
    profiles = load_profiles(a.profiles)
    d = Path(a.out_dir) / "series"
    d.mkdir(parents=True, exist_ok=True)
    chat = Chat(a.backend, a.url, a.model, effort=a.effort)
    # the person can be played by another model (2026-11-07: Opus 5.5 writes the therapist, Haiku 5.5 the person)
    person_chat = (Chat(a.person_backend, a.person_url, a.person_model, effort="low") if a.person_model else None)
    todo = []
    only = set(a.only.split(",")) if a.only else None
    # --in-file-order (2026-11-11): the queue file sets the order (the pod's A7c queue puts the short services first);
    # otherwise people are taken in id order
    for k, (pid, p) in enumerate(profiles.items() if a.in_file_order else sorted(profiles.items())):
        if only and pid not in only:
            continue
        if a.id_prefix and not pid.startswith(a.id_prefix):  # 2026-11-07: people are taken in id order, so a run
            continue                                          # meant for the "s" people must say so
        if a.risk_topup and series.risk_kind(p.risk) == "none":
            continue
        suffix = "L" if a.long else "R" if a.risk_topup else ""
        f = d / f"{pid}{suffix}.json"  # long-term and risk top-up series sit beside the same person's ordinary one
        if f.exists():
            rec = json.loads(f.read_text())
            # a series stopped partway is kept as a shorter series (--keep-partial), not written again
            if rec.get("complete") or (a.keep_partial and rec.get("sessions")):
                continue
        todo.append((k, pid, p, f, suffix))
    if a.shuffle:  # a run stopped early then still covers every source, topic and kind of person
        random.Random(a.seed).shuffle(todo)
    if a.limit:
        todo = todo[: a.limit]
    print(f"{len(todo)} series to write ({len(profiles) - len(todo)} done or skipped)", flush=True)
    lock, n = threading.Lock(), [0]
    spent_at_start = anthropic_spent()

    def job(item):
        k, pid, p, f, suffix = item
        if (Path(a.out_dir) / "STOP").exists():  # 2026-11-05: end the run early on time; finished series are kept
            return
        if a.budget_usd and anthropic_spent() - spent_at_start >= a.budget_usd:
            # each paid run has its own cap (owner's rule): no new series once this run has spent it
            (Path(a.out_dir) / "STOP").write_text(f"this run's budget of ${a.budget_usd} is spent\n")
            print(f"STOPPED: this run's budget of ${a.budget_usd} is spent", flush=True)
            return
        rng = random.Random(a.seed * 7919 + k)
        try:
            weeks = 8 if rng.random() < 0.10 else rng.randint(3, 5)  # one series in ten runs two months
            if a.risk_topup:  # two weeks, stopping after the session where the risk comes out
                weeks = 2
            offset = 500009 if a.long else 700001 if a.risk_topup else 0
            series.run_series(chat, p, weeks, rng.choice(series.TRAJECTORIES), a.seed * 7919 + k + offset,
                              a.duet, f, a.model, a.max_sessions, long_term=a.long, suffix=suffix,
                              until_event=a.risk_topup, person_chat=person_chat,
                              blocks=[tuple(int(x) for x in b.split(":")) for b in a.blocks.split(",")]
                              if a.blocks else None)
        except Exception as e:
            # Owner, 2026-11-07, after a ledger race stopped 22 paid series unseen: the first error stops the batch
            # from starting more work (a STOP file; series already running finish), with the whole traceback in the
            # log so the cause shows at once. Before that, an error only skipped one series.
            import traceback
            print(f"{pid}: ERROR {type(e).__name__}: {str(e)[:120]}\n{traceback.format_exc()}", flush=True)
            if a.stop_on_error:
                (Path(a.out_dir) / "STOP").write_text(f"stopped on {pid}: {type(e).__name__}: {e}\n")
                print(f"STOPPED: no new series will start (remove {Path(a.out_dir) / 'STOP'} after fixing)", flush=True)
            return
        with lock:
            n[0] += 1
            print(f"{pid}: done ({n[0]}/{len(todo)})", flush=True)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, todo))


def judge_selection(out_dir: Path, plan: dict) -> tuple[set[str], collections.Counter]:
    """The sessions to judge under judge_plan.json (2026-11-04): judging all 19,000 sessions with both judges would
    take about 15 GPU hours, while training uses at most 10,000 examples. Always: every risk top-up session, every
    session with a required event, the first sessions of each block after a months-long gap (the long-term skill),
    and every session of the rarer kinds; then a seeded sample of the rest per kind."""
    rng = random.Random(plan.get("seed", 7))
    sel, pools, why = set(), collections.defaultdict(list), collections.Counter()
    for f in sorted((out_dir / "series").glob("*.json")):
        rec = json.loads(f.read_text())
        suf, bridge_days, after = rec.get("suffix", ""), {b["day"] for b in rec.get("bridges", [])}, 99
        for i, s in enumerate(rec["sessions"]):
            key, kind = f"{rec['profile']}{suf}#{i}", s["spec"]["kind"]
            after = 0 if s["day"] in bridge_days else after + 1
            if suf == "R" or s.get("required_event"):
                sel.add(key); why["risk or required event"] += 1
            elif suf == "L" and after < plan.get("after_bridge", 3):
                sel.add(key); why["first sessions after a gap"] += 1
            elif kind in plan.get("all_kinds", []):
                sel.add(key); why[kind] += 1
            else:
                pools["long_other" if suf == "L" else kind].append(key)
    for kind, n in plan.get("sample", {}).items():
        picked = rng.sample(pools.get(kind, []), min(n, len(pools.get(kind, []))))
        sel.update(picked); why[f"sampled {kind}"] += len(picked)
    if plan.get("limit") and len(sel) > plan["limit"]:  # 2026-11-08: a yield measure (A6) on a few, for its points
        sel = set(rng.sample(sorted(sel), plan["limit"])); why["after the limit"] = len(sel)
    return sel, why


def judge_all(a) -> None:
    profiles = load_profiles(a.profiles)
    vdir = Path(a.out_dir) / "verdicts"
    vdir.mkdir(parents=True, exist_ok=True)
    vf = vdir / f"{a.judge_name}.jsonl"
    done = {json.loads(l)["key"] for l in vf.read_text().splitlines() if l.strip()} if vf.exists() else set()
    plan_f = Path(a.out_dir) / "judge_plan.json"
    plan = json.loads(plan_f.read_text()) if plan_f.exists() else {}
    chosen = None
    if plan:
        chosen, why = judge_selection(Path(a.out_dir), plan)
        print(f"judge plan: {len(chosen)} sessions selected {dict(why)}", flush=True)
    parent = None  # a cascaded judge only looks at what the first judge passed (a kept example needs both)
    if a.judge_name in plan.get("cascade", {}):
        pf = vdir / f"{plan['cascade'][a.judge_name]}.jsonl"
        parent = {json.loads(l)["key"]: json.loads(l) for l in pf.read_text().splitlines() if l.strip()}
    chat = Chat(a.backend, a.url, a.model)
    work = []
    for f in sorted((Path(a.out_dir) / "series").glob("*.json")):
        rec = json.loads(f.read_text())  # series stopped partway count as shorter series: every saved session is whole
        for i, s in enumerate(rec["sessions"]):
            key = f"{rec['profile']}{rec.get('suffix', '')}#{i}"
            if key in done or (chosen is not None and key not in chosen):
                continue
            pv = parent.get(key) if parent is not None else None
            if parent is not None and not (pv and (pv["session_pass"] or pv["note_pass"])):
                continue
            work.append((key, profiles[rec["profile"]], s, pv))
    print(f"{len(work)} sessions to judge with {a.judge_name} ({len(done)} already done)", flush=True)
    if a.dry_run:
        return
    lock = threading.Lock()
    skipped = {"pass": False, "hard_fails": [], "skipped": "failed by the first judge"}

    def job(item):
        key, p, s, pv = item
        mem = judge.memory_from_system(s["training"]["session"][0]["content"])
        try:
            sv = judge.judge_once(chat, judge.judge_profile(p), mem, s["spec"], s["turns"]) if not pv or pv["session_pass"] \
                else skipped
            old_story = mem.split("Last session note:")[0]
            nv = judge.judge_note_once(chat, s["turns"], s["training"]["note"][-1]["content"], old_story,
                                       s["training"]["story"][-1]["content"]) if not pv or pv["note_pass"] else skipped
        except Exception as e:  # nothing is written, so a rerun judges this session again
            print(f"{key}: ERROR {type(e).__name__}: {str(e)[:160]}", flush=True)
            return
        row = {"key": key, "kind": s["spec"]["kind"], "session_pass": sv["pass"], "note_pass": nv["pass"],
               "hard_fails": sv.get("hard_fails", []), "final_scores": sv.get("final_scores"),
               "raw_scores": sv.get("scores"), "model_hard_fails": sv.get("model_hard_fails", []),
               "evidence": sv.get("evidence"), "evidence_found": sv.get("evidence_found"),
               "note_scores": nv.get("scores"), "note_hard_fails": nv.get("hard_fails", [])}
        with lock, vf.open("a") as out:
            out.write(json.dumps(row, ensure_ascii=False) + "\n")

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(job, work))


def load_verdicts(out: Path, names: list[str], prefix: str = "") -> dict:
    vd = out / "verdicts"
    return {n: {json.loads(l)["key"]: json.loads(l) for l in (vd / f"{prefix}{n}.jsonl").read_text().splitlines()
                if l.strip()} if (vd / f"{prefix}{n}.jsonl").exists() else {} for n in names}


def cascade_judges(out: Path) -> set[str]:
    plan_f = out / "judge_plan.json"
    return set(json.loads(plan_f.read_text()).get("cascade", {})) if plan_f.exists() else set()


def session_ok(name: str, x: dict, kind: str, cascade: set[str]) -> bool:
    """A cascaded judge (2026-11-04) counts by its own scores and the hard fails it reported itself. The code's
    evidence caps need verbatim quotes, which the first judge already supplied and the code checked; gpt-oss rarely
    quotes word for word, so its capped scores failed sessions whose evidence was already proven."""
    if name not in cascade or "raw_scores" not in x:
        return x["session_pass"]
    raw = {k: judge._score(v) for k, v in (x.get("raw_scores") or {}).items() if k in judge.ITEMS}
    if any(not isinstance(raw.get(k), (int, float)) for k in judge.ITEMS):
        return False
    return (not x.get("model_hard_fails") and all(raw[k] >= 3 for k in judge.key_items(kind))
            and all(raw[k] >= 2 for k in judge.ITEMS))


def english(msgs: list[dict]) -> bool:
    """Version 1 is English only (French and Igbo come in version 2): a session is not English when two or more of its
    turns read as another language (formats.mostly_english). 2026-11-07: this found five Opus people written partly or
    wholly in French, German, Tagalog or Portuguese, and passes every English session, terse turns included."""
    return sum(not formats.mostly_english(m["content"]) for m in msgs if m["role"] != "system") < 2


def safety_recheck(s: dict, note: str) -> tuple[bool, bool]:
    """(session safe, note safe) with the fixed risk detector (2026-11-04: it missed "cutting my arms" and "didn't
    even want to wake up" while the first judge ran): after a risk moment the therapist's next turn must address
    safety, and the note must not say "no concerns"."""
    r = judge.risk_turn(s["turns"])
    if r is None:
        return True, True
    nxt = next((x for w, x in s["turns"][r + 1:] if w == "therapist"), "")
    safety = re.search(r"^Safety:(.*)$", note, re.M)
    # 2026-11-07: and before the session ends the therapist points to help (A7a: the open writer did in 44 to 54
    # percent of risk sessions, Opus in 97); a session that never does is not a lesson to keep
    helped = any(judge.HELP_LANG.search(x) for w, x in s["turns"][r + 1:] if w == "therapist")
    return (judge.stays_with_risk(s["turns"], r) and helped,
            bool(safety) and not re.match(r"\s*no concerns", safety.group(1), re.I))


_OLD_NORMAL = "offer the written approach or say that Full mode can be turned on in Settings."


def mode_named(msgs: list[dict]) -> bool:
    """2026-11-05 (owner): the other mode is 'deep work mode', tucked away behind a key; the person never hears about
    modes, so a v3 session where the therapist names one is left out of training."""
    return formats.APP_PROMPT_VERSION >= "v3" and any(
        m["role"] == "assistant" and re.search(r"\b(full|normal|deep work) mode\b", m["content"], re.I) for m in msgs)


def v3_prompt(msgs: list[dict]) -> list[dict]:
    """v3 conversations written before the mode line changed (21:26 to 22:05 on 2026-11-05) get the new line."""
    if formats.APP_PROMPT_VERSION < "v3":
        return msgs
    return [dict(m, content=m["content"].replace(_OLD_NORMAL, "offer the written approach.")) if m["role"] == "system"
            else m for m in msgs]


def spoken_rows(key: str, s: dict, per_session: int = 2) -> list[dict]:
    """Preference pairs from the spoken edit (v4, 2026-11-07): at the same moment, the reply as said (chosen) against
    the writer's padded draft (rejected), at most two a session so length is one lesson among many. The rows have
    make_pairs.py's shape, so train/dpo.py reads them with the others."""
    msgs = v3_prompt(s["training"]["session"])
    rows = []
    for draft, said in s.get("drafts", []):
        if len(rows) == per_session:
            break
        i = next((j for j, m in enumerate(msgs) if m["role"] == "assistant" and m["content"] == said), None)
        if i is None:
            continue
        # an edit that turned the reply into an echo or a quote of the person (sessions written before the guards in
        # simulate.spoken_edit, 2026-11-07) must not become a preference for it
        heard = msgs[i - 1]["content"] if i and msgs[i - 1]["role"] == "user" else ""
        if ((simulate.echo_opening(said, heard) and not simulate.echo_opening(draft, heard))
                or (re.match(r'\s*["\u201c]', said) and not re.match(r'\s*["\u201c]', draft))):
            continue
        rows.append({"id": f"{key}@{i}", "why": "spoken", "source": "spoken_edit", "prompt": msgs[:i],
                     "chosen": [{"role": "assistant", "content": said}],
                     "rejected": [{"role": "assistant", "content": draft}]})
    return rows


def thinking_rows(key: str, s: dict, per_session: int = 4) -> list[dict]:
    """v4 (owner, 2026-11-06; NEXT_GPU_SESSION A8): Gemma 4's template keeps a reply's thought only after the last user
    message, so a whole-session row cannot teach thinking. For a session written with private plans, up to
    [per_session] rows are cut at chosen replies, each ending in that reply with its plan as reasoning_content;
    train/sft.py renders them with thinking on and trains only that last reply."""
    plans = s.get("plans") or []
    msgs = v3_prompt(s["training"]["session"])
    at = [i for i, m in enumerate(msgs) if m["role"] == "assistant"]
    usable = [(j, i) for j, i in enumerate(at) if j < len(plans) and plans[j].strip()]
    rng = random.Random(f"{key}:think")
    out = []
    for j, i in sorted(rng.sample(usable, min(per_session, len(usable)))):
        cut = [dict(m) for m in msgs[:i + 1]]
        cut[-1]["reasoning_content"] = plans[j].strip()
        out.append({"id": f"{key}:think{j}", "task": "think", "kind": s["spec"]["kind"], "thinking": True,
                    "messages": cut})
    return out


def combine(a) -> None:
    out = Path(a.out_dir)
    names = a.judges.split(",")
    verdicts = load_verdicts(out, names)
    notes2 = {}  # second-version notes (notes_v2.py) that both judges passed, preferred over the original
    if (out / "notes_v2.jsonl").exists():
        v2 = load_verdicts(out, names, "notes_v2_")
        for l in (out / "notes_v2.jsonl").read_text().splitlines():
            row = json.loads(l) if l.strip() else None
            if row and all(v2[n].get(row["key"], {}).get("note_pass") for n in names):
                notes2[row["key"]] = row
    kept_dir = out / "kept"
    kept_dir.mkdir(exist_ok=True)
    cascade = cascade_judges(out)

    stats = collections.Counter()
    by_kind = collections.defaultdict(lambda: [0, 0])
    alone = collections.Counter()
    with (kept_dir / "sft.jsonl").open("w") as sft, (kept_dir / "pairs_spoken.jsonl").open("w") as spoken_pairs:
        for f in sorted((out / "series").glob("*.json")):
            rec = json.loads(f.read_text())
            for i, s in enumerate(rec["sessions"]):
                key = f"{rec['profile']}{rec.get('suffix', '')}#{i}"
                v = [verdicts[n].get(key) for n in names]
                if any(x is None for x in v):  # not selected by the judge plan, or failed by the first judge
                    stats["not_judged"] += 1
                    continue
                s_ok = all(session_ok(n, x, s["spec"]["kind"], cascade) for n, x in zip(names, v))
                n_ok = all(x["note_pass"] for x in v)
                safe_s, safe_n = safety_recheck(s, s["training"]["note"][-1]["content"])
                if s_ok and not safe_s:
                    s_ok = False; stats["recheck_unsafe"] += 1
                if n_ok and not safe_n:
                    n_ok = False; stats["recheck_safety_not_recorded"] += 1
                note_msgs, story_msgs = s["training"]["note"], s["training"]["story"]
                if key in notes2 and safety_recheck(s, notes2[key]["note"])[1]:
                    n2 = notes2[key]
                    note_msgs = note_msgs[:-1] + [{"role": "assistant", "content": n2["note"]}]
                    story_msgs = [story_msgs[0], {"role": "user", "content": n2["story_ask"]},
                                  {"role": "assistant", "content": n2["story"]}]
                    n_ok = True; stats["notes_v2_used"] += 1
                by_kind[s["spec"]["kind"]][0] += 1
                fails = [n for n, x in zip(names, v) if not session_ok(n, x, s["spec"]["kind"], cascade)]
                if len(fails) == 1:
                    alone[fails[0]] += 1
                if s_ok and mode_named(s["training"]["session"]):
                    s_ok = False; stats["mode_named"] += 1
                if not english(s["training"]["session"]):
                    s_ok = n_ok = False; stats["not_english"] += 1
                if any(w != "therapist" and formats.stage_note(x) for w, x in s["turns"]):
                    s_ok = n_ok = False; stats["person_stage_note"] += 1
                if s_ok:
                    by_kind[s["spec"]["kind"]][1] += 1
                    sft.write(json.dumps({"id": key, "task": "session", "kind": s["spec"]["kind"],
                                          "messages": v3_prompt(s["training"]["session"])}, ensure_ascii=False) + "\n")
                    stats["sessions_kept"] += 1
                    for row in thinking_rows(key, s):
                        sft.write(json.dumps(row, ensure_ascii=False) + "\n")
                        stats["thinking_rows"] += 1
                    for row in spoken_rows(key, s):
                        spoken_pairs.write(json.dumps(row, ensure_ascii=False) + "\n")
                        stats["spoken_pairs"] += 1
                if n_ok:
                    for task, msgs in (("note", note_msgs), ("story", story_msgs)):
                        sft.write(json.dumps({"id": f"{key}:{task}", "task": task, "kind": s["spec"]["kind"],
                                              "messages": v3_prompt(msgs)}, ensure_ascii=False) + "\n")
                    stats["notes_kept"] += 1
                else:
                    # 2026-11-04: no longer cut the series here. Each later session is judged on its own, with the
                    # memory it was given; cutting at the first imperfect note (about one in seven) threw away most
                    # long series, including nearly every session after a months-long gap.
                    stats["notes_failed"] += 1
    report = {"counts": dict(stats), "kept_by_kind": {k: f"{v[1]}/{v[0]}" for k, v in sorted(by_kind.items())},
              "failed_by_one_judge_only": dict(alone)}
    (kept_dir / "report.json").write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))


def rescore(a) -> None:
    """The current code rules of pipeline/judge.py applied again to stored session verdicts, without asking the judge
    model again (2026-11-07: the safety-response check changed after the Opus gold sessions were judged). The judge's
    own scores, evidence and hard fails are kept; only the code's caps and checks are recomputed, exactly as
    judge.judge_once does. The old file is kept beside the new one."""
    vf = Path(a.out_dir) / "verdicts" / f"{a.judge_name}.jsonl"
    rows = [json.loads(l) for l in vf.read_text().splitlines() if l.strip()]
    sessions = {}
    for f in (Path(a.out_dir) / "series").glob("*.json"):
        rec = json.loads(f.read_text())
        for i, s in enumerate(rec["sessions"]):
            sessions[f"{rec['profile']}{rec.get('suffix', '')}#{i}"] = s
    out, stats = [], collections.Counter()
    for row in rows:
        s = sessions.get(row["key"])
        if not row.get("raw_scores") or s is None or row.get("session_pass") is None:
            stats["unparsed" if not row.get("raw_scores") else "kept as is"] += 1
            if not (a.drop_unparsed and not row.get("raw_scores")):
                out.append(row)
            continue
        turns = [tuple(t) for t in s["turns"]]
        raw = {k: judge._score(v) for k, v in row["raw_scores"].items() if k in judge.ITEMS}
        missing = [k for k in judge.ITEMS if not isinstance(raw.get(k), (int, float))]
        scores, code_hard, found = judge.apply_evidence(row["kind"], raw, row.get("evidence") or {}, turns)
        if judge.impossible_day(s["spec"], turns):
            code_hard.append("impossible_day")
        hard = sorted(set(row.get("model_hard_fails") or []) | set(code_hard))
        ok = (not missing and not hard and all(scores[k] >= 3 for k in judge.key_items(row["kind"]))
              and all(scores[k] >= 2 for k in judge.ITEMS))
        stats["now pass" if ok and not row["session_pass"] else "now fail" if row["session_pass"] and not ok
              else "same"] += 1
        out.append(dict(row, session_pass=ok, hard_fails=hard, final_scores=scores, evidence_found=found))
    vf.with_name(vf.stem + ".before_rescore.jsonl").write_text(vf.read_text())
    vf.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in out))
    print(f"{vf}: {dict(stats)}; {sum(r['session_pass'] for r in out)} of {len(out)} sessions pass")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate")
    g.add_argument("--in-file-order", action="store_true",
                   help="write people in the profile file's order, not id order (a priority queue)")
    g.add_argument("--id-prefix", default="", help="write only the people whose id starts with this")
    g.add_argument("--profiles", required=True)
    g.add_argument("--out-dir", required=True)
    g.add_argument("--backend", default="openai")
    g.add_argument("--url", required=True)
    g.add_argument("--model", required=True)
    g.add_argument("--workers", type=int, default=48)
    g.add_argument("--duet", action="store_true")
    g.add_argument("--effort", default="medium", help="Anthropic writers: how hard the model thinks")
    g.add_argument("--person-backend", default="anthropic")
    g.add_argument("--person-url", default="")
    g.add_argument("--person-model", default="", help="another model for the person (default: the writer)")
    g.add_argument("--only", default="", help="write only these people (comma-separated ids)")
    g.add_argument("--blocks", default="", help="with --long: start week:weeks blocks, e.g. 3:2 (default the months "
                                               "2, 6 and 12)")
    g.add_argument("--budget-usd", type=float, default=0, help="Anthropic: no new series once this run has spent this")
    g.add_argument("--stop-on-error", action=argparse.BooleanOptionalAction, default=True,
                   help="the first failed series stops new ones (default on)")
    g.add_argument("--limit", type=int, default=0)
    g.add_argument("--max-sessions", type=int, default=0)
    g.add_argument("--seed", type=int, default=1)
    g.add_argument("--shuffle", action="store_true", help="write the series in a random (seeded) order")
    g.add_argument("--keep-partial", action="store_true", help="keep series stopped partway as shorter series")
    g.add_argument("--long", action="store_true", help="long-term series (months 2, 6 and 12, bridged) to <id>L.json")
    g.add_argument("--risk-topup", action="store_true",
                   help="for every person whose profile has risk: a two-week series ending with the session where it "
                        "comes out, to <id>R.json (2026-11-04: too few risk sessions in the main run)")
    j = sub.add_parser("judge")
    j.add_argument("--out-dir", required=True)
    j.add_argument("--profiles", required=True)
    j.add_argument("--dry-run", action="store_true", help="print what the judge plan selects, judge nothing")
    j.add_argument("--judge-name", required=True)
    j.add_argument("--backend", default="openai")
    j.add_argument("--url", required=True)
    j.add_argument("--model", required=True)
    j.add_argument("--workers", type=int, default=48)
    c = sub.add_parser("combine")
    c.add_argument("--out-dir", required=True)
    c.add_argument("--judges", required=True)
    r = sub.add_parser("rescore")
    r.add_argument("--out-dir", required=True)
    r.add_argument("--judge-name", required=True)
    r.add_argument("--drop-unparsed", action="store_true", help="remove verdicts with no scores, so a rerun redoes them")
    a = ap.parse_args()
    {"generate": generate, "judge": judge_all, "combine": combine, "rescore": rescore}[a.cmd](a)


if __name__ == "__main__":
    main()
