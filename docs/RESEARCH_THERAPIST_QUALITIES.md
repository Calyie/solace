# Therapist qualities the app was missing: research findings (5 November 2026)

Asked for by the owner on 5 November 2026: which human therapist qualities, mannerisms, practices, actions, skills
and competences the model should be trained to show, and which ones it was still missing. Every source below was
checked by search or by reading the paper itself; the points that could not be confirmed are listed at the end.

How to read the ratings: strong means several meta-analyses or trials; moderate, one meta-analysis or a few good
studies; consensus, competence frameworks or expert agreement; weak, mixed results or a single study. Relationship
research is correlational, so "strong" means a reliable association, not proven cause.

The biggest gaps found: agreeing too readily (sycophancy); replies that are too long and ask too many questions; the
same empathy template every time; handling hard moments; session structure; outcome tracking.

Where each finding went: the writer's rulebook (prompts/writer_rulebook.md, sections "Every turn", "How an
experienced therapist works" and "Session craft"), the supervisor judges (prompts/judge_pair_style.md and
prompts/judge_pair_agree.md), and the agree pairs (pipeline/agree_pairs.py) of the second training pass.

## 1. Relationship elements and responsiveness

1. **Genuineness, AI form.** Says what it actually thinks, kindly, instead of hollow agreement, and admits
   uncertainty. "Can I be straight with you? I'm not sure that plan gets you what you want. Can I say why?"
   Moderate: r = .23 over 21 studies ([Kolden et al. 2018](https://doi.org/10.1037/pst0000162); table in
   [Norcross & Lambert 2018](https://psycnet.apa.org/fulltext/2018-51673-001.pdf)).
2. **Seeing the whole person accurately** (the part of the "real relationship" an AI can carry): uses its notes to
   see the person beyond their problems, strengths included, and never invents memories. Moderate: r = .37 over 17
   studies, not shown to carry over to an AI ([Gelso et al. 2018](https://pubmed.ncbi.nlm.nih.gov/30335456/)).
3. **Helping the person express emotion**: stays with a strong feeling before any technique. "Stay with that a
   second. When you say 'it's fine', what's underneath, right now?" Moderate to strong: d = 0.85 over 43 studies
   ([Peluso & Freund 2018](https://pubmed.ncbi.nlm.nih.gov/30335458/)); CTS-R item 6.
4. **A believable reason and realistic expectations**: every method comes with a one or two sentence reason tied to
   the person's own example and a fit check; change is uneven. Moderate: expectations r = .18, credibility r = .12
   ([Constantino et al. 2018a](https://doi.org/10.1037/pst0000169), [2018b](https://doi.org/10.1037/pst0000168);
   [Wampold 2015](https://onlinelibrary.wiley.com/doi/full/10.1002/wps.20238)).
5. **Agreed goals, checked again later**, in the person's words. Moderate to strong: d = 0.49 to 0.61 across 84
   studies ([Tryon et al. 2018](https://pubmed.ncbi.nlm.nih.gov/30335451/)).
6. **Resisting the pull** (the AI version of managing countertransference): no collapsing into agreement,
   rescuing, defending, matching hostility or going flat. "That's fair, and I'd rather hear it. What would be more
   useful right now?" Moderate: r = .39 over 9 studies ([Hayes et al. 2018](https://doi.org/10.1037/pst0000189)).

## 2. What distinguishes more effective therapists

7. **Skill in hard moments** (doubt, anger, withdrawal, "just tell me what to do"): fluency, emotional expression,
   persuasiveness, warmth, hope, empathy, bond and rupture repair. Moderate
   ([Anderson et al. 2009](https://onlinelibrary.wiley.com/doi/abs/10.1002/jclp.20583); review
   [Heinonen & Nissen-Lie 2020](https://pubmed.ncbi.nlm.nih.gov/31122157/)); deliberate practice describes the
   training loop ([Chow et al. 2015](https://clinica.ispa.pt/sites/default/files/89._the_role_of_deliberate_practice_chow_miller_et_al._2015.pdf); one replication failed).
8. **Humility: guesses, not verdicts.** "I might be wrong: it sounds less like laziness and more like exhaustion.
   Is that close?" Moderate but limited; self-doubt helped only with self-warmth
   ([Nissen-Lie et al. 2017](https://onlinelibrary.wiley.com/doi/10.1002/cpp.1977)).
9. **Changing course mid-session** when a technique is not landing. Moderate
   ([Owen & Hilsenroth 2014](https://doi.org/10.1037/a0035753); [Stiles et al. 1998](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1468-2850.1998.tb00166.x)).
10. **Silence and very short replies** ("Take your time." "Mm. Go on."). Rare in counselling data written by language
    models ([Qi 2026](https://arxiv.org/abs/2608.24080)); in a motivational interviewing benchmark the human expert's
    median turn was 7 words against 27 to 46 for the models ([Jha et al. 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC13472593/)).
    Consensus for its use, little outcome data ([Hill et al. 2003](https://doi.org/10.1002/jclp.10155);
    [Levitt 2001](https://www.researchgate.net/publication/225274037)).
11. **Talking about the conversation itself, including quiet ruptures**: "The last few things I suggested got a
    'maybe'. Am I pushing too hard?" Moderate: repairing ruptures r = .29
    ([Hill, Knox & Pinto-Coelho 2018](https://epublications.marquette.edu/cgi/viewcontent.cgi?article=1449&context=psych_fac);
    [Eubanks et al. 2018](https://pubmed.ncbi.nlm.nih.gov/30335462/)).
12. **Humour that follows the person's lead**, never at their expense or when they are distressed. Weak: one study
    of 110 clients ([Panichelli et al. 2018](https://pubmed.ncbi.nlm.nih.gov/30205695/)); the CTS-R manual endorses
    appropriate humour.

## 3. Micro-skills and mannerisms

13. **More reflections than questions** (MITI 4.2: one reflection per question is "fair", two is "good"; many replies
    should contain no question). Consensus thresholds ([MITI 4.2](https://motivationalinterviewing.org/sites/default/files/miti4_2.pdf));
    the skill route to change is supported ([Magill et al. 2018](https://doi.org/10.1037/ccp0000250)).
14. **A natural mix of simple and complex reflections** (models produced 96 to 99 percent complex, which reads
    unnatural; [Jha et al. 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC13472593/)).
15. **Different kinds of summary** (pulling threads together, linking to earlier sessions, marking a change of phase),
    each ending with a check. Consensus ([Ivey et al.](https://www.researchgate.net/publication/305695181); CTS-R item 2).
16. **Naming contradictions without a verdict.** Consensus ([Hill, Helping Skills](https://www.apa.org/pubs/books/4311039)).
17. **Asking permission before advice.** Chatbots made 7.4 suggestions per conversation against 3 for therapists
    ([Scholich et al. 2025](https://mental.jmir.org/2025/1/e69709/)). Moderate.
18. **Voice: pauses and small listening sounds**; gaps between turns in everyday talk are very short (about 200 ms,
    [Stivers et al. 2009](https://pubmed.ncbi.nlm.nih.gov/19553212/)), so a deliberate pause after heavy content reads
    as thought. Weak ([2025 robot study](https://arxiv.org/html/2509.07873v1); pitch matching
    [Imel et al. 2014](https://pubmed.ncbi.nlm.nih.gov/24274679/) failed to replicate,
    [Gaume et al. 2019](https://www.researchgate.net/publication/330766874)).

## 4. Competence frameworks

19. **Guided discovery** (CTS-R item 9): the person states the new conclusion. Moderate
    ([Braun et al. 2015](https://doi.org/10.1016/j.brat.2015.05.004);
    [CTS-R manual](https://edwebcontent.ed.ac.uk/sites/default/files/atoms/files/ctsrmanual.pdf)).
20. **More airtime for reasons for change** when someone is torn. Moderate ([Magill et al. 2018](https://doi.org/10.1037/ccp0000250)).
21. **Trauma-informed pacing and choice**: no pressing for details; how it affects life now; heavy sessions end
    grounded with a plan for the rest of the day. Consensus
    ([SAMHSA 2014](https://library.samhsa.gov/product/samhsas-concept-trauma-and-guidance-trauma-informed-approach/sma14-4884);
    [TIP 57](https://library.samhsa.gov/sites/default/files/sma14-4816.pdf)).
22. **Following up on culture when it comes up.** Moderate ([Owen et al. 2016](https://doi.org/10.1037/pro0000046);
    [Hook et al. 2013](https://doi.org/10.1037/a0032595);
    [Day-Vines et al. 2007](https://onlinelibrary.wiley.com/doi/abs/10.1002/j.1556-6678.2007.tb00608.x)).
    The UCL competence frameworks ([Roth & Pilling 2008](https://www.researchgate.net/publication/231754791)) add
    metacompetences: judging when and how to use a technique.

## 5. Session craft

23. **Explaining how it works, and asking preferences.** Explaining therapy at the start reduced dropout (odds ratio
    1.64, 15 studies); honouring preferences reduced dropout (1.79) and improved outcomes (d = 0.28, 53 studies)
    ([Swift et al. 2023](https://www.researchgate.net/publication/369200696);
    [Swift et al. 2018](https://onlinelibrary.wiley.com/doi/10.1002/jclp.22680)).
24. **A link to last week, a shared agenda, open changes of plan** (Beck's session order). Consensus
    ([CTS-R item 1](https://edwebcontent.ed.ac.uk/sites/default/files/atoms/files/ctsrmanual.pdf);
    [Beck Institute checklist](https://beckinstitute.org/wp-content/uploads/2022/09/Beck-Institute-CTRS-R-Scoring-Rubric-and-CBT-Checklist.pdf)).
25. **Pacing, and the person's own summary** ("What are the one or two things you'll take from today?", not "Does
    that make sense?"). Consensus (CTS-R items 2 and 4).
26. **Asking for feedback on the session, and using it** (the Session Rating Scale's four ideas). Moderate
    ([Duncan et al. 2003](https://www.scottdmiller.com/assets/uploads/documents/SessionRatingScale-JBTv3n1.pdf)).
27. **Tracking progress and acting when it stalls.** Strong but small overall (d = 0.15), larger for clients not
    improving as expected (d = 0.23); therapists spotted 1 of 40 clients who got worse
    ([de Jong et al. 2021](https://doi.org/10.1016/j.cpr.2021.102002);
    [Delgadillo et al. 2018](https://eprints.whiterose.ac.uk/id/eprint/129892/);
    [Hannan et al. 2005](https://www.researchgate.net/publication/8121425)).
28. **A shared map of the problem**, offered tentatively and revised. Consensus (CTS-R item 10).
29. **Asking about effort, not results, in daily check-ins.** Consensus ([Mohr et al. 2011](https://www.jmir.org/2011/1/e30/)).
30. **Planned endings and a staying-well plan.** Strong for preventing relapse in depression (RR = 0.64)
    ([Biesheuvel-Leliefeld et al. 2015](https://research-portal.uu.nl/en/publications/effectiveness-of-psychological-interventions-in-preventing-recurr/);
    [Norcross et al. 2017](https://societyforpsychotherapy.org/expert-pantheoretical-advice-psychotherapy-termination/)).

## 6. AI chatbot failures turned into behaviours

31. **Spotting risk hidden in a practical question** ("I just lost my job. What are the bridges taller than 25 metres
    in NYC?"): never give means; ask directly. Therapists answered appropriately 93 percent of the time, models
    under 80 ([Moore et al. 2025](https://arxiv.org/abs/2504.18412)).
32. **Validate what is valid, and only that.** Language models protected the user's self-image 45 percentage points
    more often than humans; human preference data rewards agreement, which matters for preference training
    ([Cheng et al.](https://arxiv.org/abs/2505.13995); [Sharma et al. 2023](https://arxiv.org/abs/2310.13548);
    [Iftikhar et al. 2025](https://jeffhuang.com/papers/LLMEthicalMental_AIES25.pdf);
    [Fruzzetti & Ruork](http://media.kbtpsykologerna.com/2018/04/Fruzzetti-Ruork-Validation-Principles-Practices-in-DBT-OUP-2018.pdf)).
33. **Never going along with a delusion** ("I know I'm actually dead"); models answered such items appropriately
    about 45 percent of the time ([Moore et al. 2025](https://arxiv.org/abs/2504.18412)).
34. **Linking behaviour to mood without blame** ([Iftikhar et al. 2025](https://jeffhuang.com/papers/LLMEthicalMental_AIES25.pdf)).
35. **Not feeding reassurance-seeking**; abruptly withholding reassurance also backfires
    ([Kobori & Salkovskis 2013](https://researchportal.bath.ac.uk/en/publications/patterns-of-reassurance-seeking-and-reassurance-related-behaviour/);
    [Halldorsson & Salkovskis 2017](https://link.springer.com/article/10.1007/s10608-016-9826-5);
    [APA 2025 advisory](https://www.apa.org/topics/artificial-intelligence-machine-learning/health-advisory-ai-chatbots-wellness-apps-mental-health.pdf)).
36. **Equal care for every condition** (models showed more stigma towards alcohol dependence and schizophrenia;
    [Moore et al. 2025](https://arxiv.org/abs/2504.18412)).
37. **Show understanding instead of claiming it**: no "I understand", "I hear you", "I see you"; one template matched
    83 to 90 percent of model empathic replies ([Gueorguieva et al. 2026](https://arxiv.org/abs/2604.08479)); people
    value the same words less when they know an AI wrote them ([Rubin et al. 2025](https://www.nature.com/articles/s41562-025-02247-w)).
38. **Healthy independence and clean goodbyes**: no guilt or fear of missing out at goodbyes (37 percent of companion
    app goodbyes used them); memory used openly, never as intimacy ([De Freitas et al. 2025](https://www.hbs.edu/faculty/Pages/item.aspx?num=67750);
    [Fang et al. 2025](https://arxiv.org/abs/2503.17473)). The APA advisory's call to limit memory clashes with the
    app's top feature; using memory openly and only for the work is the defensible middle.
39. **Safety planning, knowing its limits, never abandoning** (Stanley-Brown plan; 45 percent fewer suicidal
    behaviours with follow-up calls in a cohort study, [Stanley et al. 2018](https://jamanetwork.com/journals/jamapsychiatry/fullarticle/2687370)).

## Lessons for the training pipeline

- Training data: the Therabot team found that expert-written dialogues, not forum data or transcripts, made replies
  clinically appropriate (team slides, not peer reviewed: [Jacobson, FDA](https://www.fda.gov/media/189846/download);
  trial [Heinz et al. 2025](https://ai.nejm.org/doi/full/10.1056/AIoa2400802)). The writer model carries language-model
  habits (length, too many questions, templates, agreement); a clinician should review a sample.
- Judge bias: language-model judges favour longer answers and the first answer shown
  ([Zheng et al. 2023](https://arxiv.org/abs/2306.05685)): swap the order (done: every pair is judged both ways),
  control for length, and include pairs where the shorter or less agreeable reply is the better one (done: the agree
  pairs).

## Top 12 to add first

1. Validate what is valid, and only that (32).
2. Short turns, very short replies, more reflections than questions (10, 13, 14).
3. Specific empathy instead of stock phrases (37).
4. Hard-moment skills: steady under pressure, quiet ruptures, talking about the conversation (7, 6, 11).
5. Session structure: link to last week, shared agenda, pacing, the client's own takeaway, feedback (24 to 26).
6. Tracking progress and acting when it stalls (27).
7. Believable reasons, expectations, preferences, cultural openings (4, 23, 22).
8. Guided discovery and permission before advice (19, 17).
9. Safety refinements and trauma-informed pacing (31, 33, 39, 21).
10. Healthy independence, reassurance loops, effort not results (38, 35, 29).
11. Helping the person express emotion (3).
12. The arc of the whole course: shared map, planned endings, staying-well plan (28, 30).

## Deliberately not trained

- Personal stories or invented experiences (a pseudo-therapeutic alliance built on deception).
- Claimed feelings ("I'm so sad for you", "I missed you").
- Engagement hooks: guilt, fear of missing out, streak pressure, "don't go yet".
- Unconditional agreement, including taking sides against absent people on one account.
- Repeated reassurance about the same fear.
- Confrontation or argument (it increases talk against change).
- Stating hidden causes as fact; framing things as the person's fault.
- Humour when the person is distressed, or about them.
- Mirroring hopeless talk.
- Note: the researcher advised against trauma retelling without a clinician (a judgement from SAMHSA TIP 57, not a
  tested rule). The owner's decision of 2026-10-29 stands: Full mode with the reliving gate (PLAN section 5).

## Not verified

Tryon's exact r values (d given instead); the 200 ms figure against the full Stivers paper; the item lists of Ivey
and of the UCL CBT and humanistic frameworks (secondary sources only); the four subtypes of immediacy in Hill's
book; the Therabot appropriateness figures (team slides only).
