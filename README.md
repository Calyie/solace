# Solace

> **Work in progress.** This repository is a display copy of an ongoing project, shared for review. It is not ready to
> build, install or use, and parts of the project are deliberately left out (see "What this copy leaves out").

**A private AI therapist and coach that runs entirely on the person's own device.**

Solace talks with a person by text or voice. In the first session it builds a plan with them; in every later session
it works through that plan, for weeks or months if needed, using methods research shows work: CBT, behavioural
activation, exposure and response prevention, CBT for insomnia, problem solving, DBT skills, ACT, self-compassion,
motivational interviewing and habit design. It remembers every session through its own notes and a therapy record the
person can read and edit.

The therapist model is a fine-tuned **Gemma 4** (E4B "Standard" and E2B "Light"), run on the device by llama.cpp.
Nothing the person says leaves the device.

<p align="center">
  <img src="app/test/goldens/01_today_new.png" width="230" alt="Today">
  <img src="app/test/goldens/03_session.png" width="230" alt="A session">
  <img src="app/test/goldens/13_call.png" width="230" alt="A call">
</p>

> Solace is not a medical device, a licensed clinician or an emergency service. It does not diagnose or prescribe.

## Why it exists

Traditional therapy is often slow and passive: weeks of listening, exploring and questions, and few concrete tools to
actually solve the problem. Solace is built to be the opposite. It is **solution-based**: when someone brings a
problem, the therapist names the research-backed method that fits (CBT, behavioural activation, exposure and response
prevention, CBT for insomnia, problem solving, DBT skills, ACT, self-compassion, motivational interviewing, habit
design), explains plainly why it works, shows step by step how to do it in their life, and does the work with them in
the session. It asks a question only when it truly needs the answer, builds a plan with the person in the first
session, and keeps working through that plan with them over weeks or months.

Solace supports people with everyday mental-health problems; it does not replace clinical care, diagnosis or
emergency help.

## What the work involved

- **The therapist standard.** A written standard for the therapist (solution-based, plan-driven, warm, never a
  questionnaire, never a sounding board), turned into the app's system prompt (`prompts/app_system_v5.txt`), a
  rulebook for writing training sessions (`prompts/v5/`), and 31 expert playbooks, one per service, each grounded in
  the published evidence (`prompts/services/`, sources in `docs/SERVICE_SOURCES.md`).
- **Training data and training.** Multi-session therapy series, judged strictly, then fine-tuning and export to
  small phone files; see "Training data and architecture" below.
- **Evaluation that adapts.** Live conversations in which a simulated person answers each reply as a real person
  would, simulated hard users, and blind judging of transcripts against hand-written reference sessions. Fixed
  scripts of user messages were rejected as a test, because they stop making sense after the first few turns.
- **The app.** A Flutter app for iPhone, Android, Mac and Linux: the therapist, voice calls, encrypted memory, the
  plan view, the check-in, practices, and an encrypted transfer between the person's own devices (`app/`).
- **Privacy by design.** The standard build has no network code or network permission at all, and tests enforce it.
  An optional separate build can use the model on the person's own computer, only over their home network or a
  private VPN, never the open internet (`home_server/`).

## Training data and architecture

**The training sessions.** The model learns from multi-session therapy series between simulated people and the
therapist: a first session that builds the plan, then check-ins and weekly sessions weeks or months in, each followed
by the note and the therapy record the app asks the model to write. The series are written to the rulebook, partly by
open models and, for the gold standard, by hand in Claude Code sessions; every session then passes code gates (no runs
of questions, no time limits, no mood numbers, spoken sentences) and a strict judge, and only passed sessions are
trained on. The current round trains on 145 judged sessions (867 rows with their notes and records).

**Public datasets that shaped it.**
- **CACTUS** (31,577 CBT counselling dialogues with intake forms): seeds for realistic simulated people and their
  intake histories, and everyday lines for checking the safety check does not raise false alarms.
- **Thousand Voices of Trauma** (3,000 prolonged-exposure therapy conversations): seeds for people with trauma
  histories and the shape of exposure work.
- **Graph2Counsel**: counselling knowledge graphs used as extra seeds for people.
- **MindGuard** (Sword Health): the training set of the optional safety check, relabelled message by message.
- **CounselingBench, CBT-Bench and CounselBench-Adv** (with expert labels): held-out evaluation only, never trained on.
- **PsychoCounsel-Preference** (36,653 preference pairs): studied and deliberately *not* trained on, because its
  preferred answers are long written advice essays, the opposite of a spoken, solution-based therapist.
- Each of the 31 services also has an expert playbook built from the clinical literature (`docs/SERVICE_SOURCES.md`).

**The training architecture.**

```mermaid
flowchart TD
    subgraph Standard["The therapist standard"]
        S1["Owner's requirements:<br/>solution-based, plan over months,<br/>never a questionnaire"]
        S2["App system prompt<br/>+ writing rulebook"]
        S3["31 evidence-based<br/>service playbooks"]
        S1 --> S2
        S3 --> S2
    end
    subgraph Data["Training data"]
        D1["Simulated people<br/>(seeded from CACTUS,<br/>Thousand Voices, Graph2Counsel)"]
        D2["Multi-session series:<br/>first session builds the plan,<br/>later sessions work it,<br/>note + record after each"]
        D3["Code gates<br/>(question runs, time talk,<br/>mood numbers, lists)"]
        D4["Strict judge<br/>(only passes are kept)"]
        D1 --> D2 --> D3 --> D4
    end
    subgraph Train["Training"]
        T1["Gemma 4 QAT base<br/>E4B Standard / E2B Light"]
        T2["Supervised fine-tuning<br/>4-bit LoRA, rank 32"]
        T3["Merge into bf16"]
        T4["Preference pairs:<br/>the model's own faulty replies<br/>vs the judged reply"]
        T5["Optional DPO round"]
        T1 --> T2 --> T3
        T3 --> T4 --> T5
    end
    subgraph Ship["Phone file"]
        P1["GGUF Q5_K_M<br/>with importance matrix"]
        P2["Drift check:<br/>KL divergence vs full model"]
        P3["Signed model list<br/>(Ed25519)"]
        P4["On the device:<br/>llama.cpp, fully offline"]
        P1 --> P2 --> P3 --> P4
    end
    subgraph Eval["Evaluation"]
        E1["Live conversations:<br/>a simulated person answers<br/>each reply"]
        E2["Simulated hard users"]
        E3["Blind judge vs<br/>hand-written references"]
        E4["Held-out public benchmarks"]
    end
    S2 --> D2
    S3 --> D2
    D4 --> T2
    T3 --> P1
    T5 --> P1
    P1 --> E1
    P1 --> E2
    E1 --> E3
    E2 --> E3
    P1 --> E4
    E3 -- "failures found become<br/>corrections and new sessions<br/>for the next round" --> D2
```

## Where it stands (honestly)

Each number below comes from a single test run, so it is a signal, not a stable result.

| | Replies ending in a question (median) | Judge score, 1 to 5 |
|---|---|---|
| The first shipped model | 99% | 2.5 |
| Release 1.4.0, Standard | 40% | 4.2 |
| Current training round, Standard | 30% | 4.6 |
| Hand-written reference sessions | about 27% | |

The current round was trained on sessions written to fix the failures these hard-user scenarios expose, so part of
its gain may not carry over to new situations; live conversations read by a blind judge are the real check. Known
gaps: the Light model still asks too many questions and sometimes hands the work back to the person, plans are not
always given their length until asked, and the record written after a session can state things that did not happen.

## What is in this copy

| Folder | What it holds |
|---|---|
| `app/` | The Flutter app's source (part of it) |
| `home_server/` | The optional home gateway's source (part of it) |
| `prompts/` | The app's system prompts, the writing rulebook, the 31 service playbooks and the judges |
| `pipeline/` | Parts of the training-data pipeline |
| `train/` | Parts of the training code |
| `tests/` | Evaluation probes and the people they use (all fictional) |
| `docs/` | The services and their sources, research on what makes a good therapist, the design of the practices, a sample of model sessions read for a clinician, and design prototypes |

## What this copy leaves out

Build and release tooling, the training and test infrastructure, operational guides, internal reviews and logs,
trained model files and datasets, and any file that held details of the machines and accounts the project runs on.
Some source files are missing for the same reason, so the code here does not build. The full project is kept
privately.

## Acknowledgements

Solace was designed and directed by Calyie and built with **Claude** (Anthropic) through Claude Code: much of the
app's code, the training pipeline, the hand-written training sessions, the reviews and the documentation were written
with Claude. It stands on Gemma 4 (Google), llama.cpp, Flutter, sherpa-onnx with Kokoro voices, ONNX Runtime and
Unsloth, and on the open counselling datasets credited in `docs/SERVICE_SOURCES.md`.

## Licence

Not licensed for reuse yet. This copy is shared for review only; all rights reserved.
