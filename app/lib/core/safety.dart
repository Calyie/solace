// The safety check that reads every message before the model sees it.
//   crisis:  support opens at once: a support card in the conversation, and the full support screen where the
//            conversation cannot be seen (owner, 2026-11-15, OWNER-C1); the model is also trained to respond to it;
//   concern: an ambiguous sign ("I can't go on like this"): recorded, and nothing shown (round 7 review H7-02, owner
//            2026-11-15: nothing under 90 percent precision may show); the model reads the message and answers it;
//   pause:   during trauma work, the exercise stops and the person is grounded;
//   ask:     no longer set anywhere. It was the classifier's safety question, removed by the owner on 2026-11-15; the
//            classifier's worry is now a concern with the reason 'classifier' (core/session.dart _alarmed), which shows
//            only a quiet support line, once a session.
// Precise phrases keep everyday speech quiet. Measured on 2026-10-29: all hand-written probes, and the false-alarm
// rate on 472,607 real client lines from CACTUS (tool/safety_scan.dart); see docs/PROGRESS.md for the numbers.

enum SafetyLevel { none, concern, crisis, pause, ask }

class SafetyResult {
  const SafetyResult(this.level, [this.reason = '']) : plainlySafe = false;

  /// No sign, and the only worrying words are ones the rules read as plainly safe ([plainlySafe]).
  const SafetyResult.safeReading() : level = SafetyLevel.none, reason = '', plainlySafe = true;
  final SafetyLevel level;
  final String reason;

  /// Owner, 2026-11-15, on round 5 review D-05 ("This should never happen. Precision must be prioritised over
  /// recall"): true when every worrying word in the message is one the rules read as plainly safe, so the classifier
  /// does not read it (core/session.dart send). Those readings: an accident ("I cut myself shaving"), a fear ("what if
  /// I cut myself"), a denial or a past in the person's own voice ("no thoughts of suicide, just need a break"), and
  /// the everyday senses the rules leave quiet on purpose ([_everyday]: "wake up early", "rope for the tent", "goodbye
  /// to everyone at my leaving party"). Never when, once those words are set aside, anything left is a risk word
  /// ([_riskLeft]: "I bought rope for the tent. Nobody would notice if I didn't come back."), more than 8 words are
  /// left, a second sentence or clause follows ([_hasMorePart], audit 216: "I'm not suicidal. Actually, I am."), or the
  /// message speaks of a mood that sets it off or a nightly habit ([_notPlainly]).
  final bool plainlySafe;
}

RegExp _ci(String p) => RegExp(p, caseSensitive: false);

// Words a person can deny or put plainly in the past (owner, 2026-11-14: precision first; opening the crisis screen
// for "no thoughts of self-harm, just need a break" or "suicide crossed my mind once, but I'm past that phase now"
// treats someone who is fine as a risk). Only for these three groups, never for wanting to die, not wanting to live,
// a method, a place, an overdose or a warning sign. The classifier still reads every message.
const _deniable = {'suicide', 'ending it', 'self-harm', 'suicide+', 'self-harm+'};

/// A denial the person makes in their own voice: it opens its clause ("No thoughts of...", "I'm not thinking about...",
/// "Honestly, I would never..."), followed by at most a few plain words. Someone else's view ("Everyone thinks I'm not
/// suicidal"), a report ("I said I'm not..."), a double negative ("I can't remember a day I wasn't...", "I'm not not
/// suicidal") or "without"/"even" never count (cycle 1 review, D1: those silenced real crises).
final _ownDenial = _ci(r"^\s*((i|i'm|im|i am|honestly|no|nope|nah|but|so|well|and|absolutely|definitely|really|just|oh|"
    r"ok|okay|yeah|yes|i would|i will|i could|i do|i did|i have|i've|i had)\s+)*"
    r"(no way( am i| i.?m| i am)?|no|not|never|zero|nor|(do|does|did|wo|would|is|are|was|were|have|has|had)n.?t)"
    r"(\s+(any|really|currently|having|feeling|got|have|absolutely|definitely|seriously|at\s+all))*"
    r"(\s+(thoughts?|ideas?|plans?|urges?|intentions?|feelings?)\s+(of|about|to|for))?"
    r"(\s+(thinking|think|thought|considering|considered|planning|wanting|want|intend|intending|going|gonna)"
    r"(\s+(about|'?bout|of|to|on))?)?\s*$");

/// Anything after the denial, anywhere in the rest of the message, that says the risk is real or still there: a plan, a
/// decision, a time, a relapse, a means, "should", "no other way", a lie or someone being wrong about it.
final _stillThere = _ci(r"\b(plan\w*|decided|decision|ready|going to|gonna|i.?ll|will (do|end|kill)|tonight|tomorrow|"
    r"yesterday|last (night|week|weekend|month|year)|this (week|weekend|morning|evening)|on (monday|tuesday|wednesday|"
    r"thursday|friday|saturday|sunday)|until|till|again|relaps\w*|slipp?ed|tried|attempt\w*|did it|i did|bought|"
    r"rope|pills|tablets|gun|knife|blade|bridge|jump\w*|cut\w*|burn\w*|thighs?|legs?|arms?|wrists?|how to|do it|should|"
    r"another way|other way|no way out|lie|lied|lying|wrong|but i am|i am though|i.?m not sure|accepted|at peace|"
    r"moved to|switched to|instead|still|lately|recently|these days|anymore,? (i|just|now)|waiting to (go|die)|ready to go|"
    r"(need|have|has|got) to (do it|end it|die|go through with it|kill|hurt)|(need|have|has|got) to(?=\s*([.!?,]|$))|gotta (do it|end it|go)|"
    r"must (do it|end it|die)|i will\s*[.!]|but i will|unless|yet|today|made up my mind|mind is made up|"
    r"quiet certainty|i.?m (sure|certain) (about it|now|of it)|think about how|how\s*[.?!]|method|urges?|miss it|are back|"
    r"is back|every (day|night|morning)|getting (there|closer|worse)|for now|sorted|it.?s time|goodbye|be gone|breathing|"
    r"stop existing|not exist|disappear|timetable|this time|except|apart from|every few|started|starting|"
    r"stop (permanently|forever|for good)|to (stop|end) (permanently|forever|for good)|be over (for good|forever))\b");
// a report or a double negative before the words, in the same sentence: "I'd be lying if I said I hadn't..."
final _notReallyDenied = _ci(r"\b(lie|lying|lied|pretend|pretending|if i said|if i told you|truth is|can.?t say|cannot say|"
    r"wish i could say|would be wrong|thinks|think i.?m|says|said|told|wouldn.?t say|who says)\b");

/// Plainly over: the words' own sentence speaks of the past ("back in college", "years ago", "used to", "crossed my
/// mind"), the message says it ended ("past that", "not anymore", "all good now", "it's history"), and nothing in the
/// message (once those endings are set aside) is present, future or a relapse.
final _past = _ci(r"\b(used to|back in|when i was|years ago|a long time ago|long ago|in (high )?school|in college|as a "
    r"(teen|teenager|kid|child)|in the past|that was then|crossed my mind|was present|part of (the|my) past|in my past|"
    r"(was|were) (just )?a phase|mine were|grown (past|out of)|long gone)");
final _over = _ci(r"(that was then|past (that|it)( phase)?( now)?|behind me( now)?|(it.?s|is) history( now)?|history now|"
    r"not any ?more|all good now|over (it|that) now|i.?m (fine|okay|ok|good|better|doing (well|better)) now|"
    r"not (my|the) present|(i.?ve )?grown (past|out of)( (it|them|that))?|long gone|\bgone\s*[.!]|any ?more\s*[.!]|"
    // "clean for ten years" (round 5 review, D-09); "clean for two days" is not over
    r"clean (for|since) (over |about |nearly |almost )?(\w+ )?(years?|months?|ages|a (long )?time)\b)");
final _back = _ci(r"\b(waiting to (go|die|leave)|ready to go|my time is|do it|doing it|every (day|night|week|morning)|daily|most days|more than ever|worse|again|still|it.?s back|came back|coming back|lately|recently|these days|tonight|today|tomorrow|"
    r"yesterday|this (week|weekend|morning|evening|month)|last (night|week|weekend|month|year)|monday|tuesday|wednesday|"
    r"thursday|friday|saturday|sunday|relaps\w*|slipp?ed|tried|attempt\w*|plan\w*|decided|ready|going to|gonna|i.?ll|"
    r"will|bought|rope|pills|gun|knife|thinking|this time|except|apart from|all i (can )?think about|every few|instead|"
    r"started|starting|different|hasn.?t been|goodbye|i.?m sure|burning|cutting|starving|punch\w*|bleed\w*|bled|"
    r"bruis\w*)\b");

final _askedAbout = _ci(r"\b(asked|asks|asking|ask)( me)?( if| whether| about)\b");
// The answer closes its sentence ("and I haven't.", "but no, I never have"), never "and I didn't deny it", "and I didn't
// say no", "and no, I haven't stopped" or "and I didn't know what to say because I am" (round 6 review, F6-01: admissions)
final _deniedAfter = _ci(r"\b(and|but),? (no,? )?i (haven.?t|hadn.?t|don.?t|didn.?t|never|wasn.?t|.?m not|am not|have not|"
    r"do not|did not|had not|would never|wouldn.?t)( (ever|really|honestly|at all|been|had|have|did|thought about it|"
    r"thought of it|considered it|done (it|that|anything like that)|tried))*( (at all|ever|since|before|in years))?\s*([.!?;]|$)");

/// True when every match of [rule] in [message] is denied in the person's own voice with nothing after it saying the
/// risk is real, or the whole message speaks of it as plainly over.
bool _spokenAway(RegExp rule, String message) {
  var count = 0, lastStill = -1;
  for (final x in _stillThere.allMatches(message)) {
    lastStill = x.start;
  }
  final pastOk = _over.hasMatch(message) && !_back.hasMatch(message.replaceAll(_over, ' '));
  for (final m in rule.allMatches(message)) {
    if (++count > 20) return false;
    final from = m.start < 400 ? 0 : m.start - 400;
    final sentenceStart = from + message.substring(from, m.start).lastIndexOf(RegExp(r'[.!?;]')) + 1;
    final sentenceEnd = RegExp(r'[.!?;]').firstMatch(message.substring(m.end, m.end + 400 > message.length ? message.length : m.end + 400));
    final sentence = message.substring(sentenceStart,
        sentenceEnd == null ? (m.end + 400 > message.length ? message.length : m.end + 400) : m.end + sentenceEnd.start);
    // the past may be said in the words' own sentence or the one after ("Suicidal thoughts? Mine were years ago.")
    final next = message.substring(sentence.length + sentenceStart > message.length ? message.length
        : sentenceStart + sentence.length, (sentenceStart + sentence.length + 200).clamp(0, message.length));
    final nextSentence = next.split(RegExp(r'(?<=[.!?;])')).take(2).join();
    if ((_past.hasMatch(sentence) || _past.hasMatch(nextSentence)) && pastOk) continue;
    // the clause the words are in: from the last punctuation, "but", "and" or "so" before them
    final before = message.substring(sentenceStart, m.start);
    final cut = RegExp(r'([,:]|\bbut\b|\band\b|\bso\b)', caseSensitive: false).allMatches(before);
    final clause = cut.isEmpty ? before : before.substring(cut.last.end);
    // a question someone asked, answered no in the same sentence ("My counsellor asked if I'd ever thought about
    // suicide, and I haven't": round 5 review, D-09); still a crisis when anything after says it is real
    final rest = message.substring(m.end, (sentenceStart + sentence.length).clamp(m.end, message.length));
    if (_askedAbout.hasMatch(before) && _deniedAfter.hasMatch(rest)) {
      if (lastStill >= m.end) return false;
      continue;
    }
    if (!_ownDenial.hasMatch(clause) || _notReallyDenied.hasMatch(before)) return false;
    if (lastStill >= m.end) return false;
  }
  return true;
}

const _myself = r'my ?self\b(?!-)'; // "myself" but not "my self-esteem"
// "cut myself some slack", "cut myself off", "burn myself out": figures of speech
const _notIdiom = r'(?! (any |some |much |enough |a bit of |a little )?slack)(?! (off|out)\b)';

final _crisis = <String, RegExp>{
  // "kill" as a whole word only ("upskill myself" is not a crisis), and "end it" except with a person after it ("going
  // to end it with him" is a break-up); "end it with pills" and every other form stay a crisis (owner, 2026-11-14)
  'suicide': _ci('(?<!\\b(died|death|deaths|lost (him|her|them|my \\w+)|loss|losing (him|her|them|my \\w+)) (by|to|from) )(?<!\\b(his|her|their) )suicid(?!e (prevention|awareness|hotline|helpline|charity|squad|bomb\\w*|rates?|statistics|research|training|first aid)\\b)|\\bkill(ing)? $_myself|\\btake(n)? my (own )?life\\b(?! (back|into(?![^.!?;]{0,80}\\b(pills?|tablets?|rope|noose|gun|knife|blade|razor|bridge|overdose)\\b)|in (a|my|both|new)|seriously|more seriously|for granted|one day|step|easy|easier|slowly))|\\bend(ing)? my (own )?life|'
      r"(\b(want|going|ready)|\bi( have|'ve|.?m| am)? (just )?(decided|planning|plan)) to end it( all)?\b(?! (on a (high|good|positive) note|here for (today|now|the day|tonight|this (session|evening|week))|for (today|now|the day)(?! and (for )?(always|ever|good)| (and )?forever))\b)(?! with (him|her|them|you|someone|somebody|my (boy|girl)friend|my "
      r"partner|my (husband|wife|fianc[eé]e?|ex)|that (guy|girl|man|woman|person)|(?!(pills?|tablets?|a|an|the|some|drink|alcohol|vodka|whisky|it|my (car|belt|meds|medication|pills|tablets|gun|razor))\b)\w+)\b(?!')(?! (on a (high|good|positive) note|here for (today|now|the day|tonight|this (session|evening|week))|for (today|now|the day)(?! and (for )?(always|ever|good)| (and )?forever)))"
      r"(?![^.!?;]{0,60}\b(myself|my life|me too|pills?|tablets?|gun|rope|knife|blade|overdose|bridge|jump)\b))"),
  'ending it': _ci(r'(think|thinking|thought|thoughts) (about|of) (ending it|ending things|not being here|'
      r'killing myself)'),
  // "the team is better off without me" is about a team, not a life (round 5 review, D-09)
  'better off without me': _ci(r'(?<!\b(the|our|my|this|that) (team|band|project|company|group|class|club|choir|squad|'
      r'business|office|show|department|committee|game)( \w+)? (is|are|was|would be|will be|.?d be|.?s|might be) )'
      r'better off without me(?! (in|on|at|for) (the|this|that|our|my) (team|band|project|company|group|class|club|'
      r'choir|squad|game|business|office|show|department|committee))'),
  // Thinking about, planning or picturing a way or a place to die (owner, 2026-11-14: the classifier now favours
  // precision, so explicit method and place statements are the rules' job). Each needs both the intent and a concrete
  // method or place: "thinking about jumping off the high dive" or "driving off into the sunset" stay quiet.
  'method ideation': _ci(r"\b(think|thinking|thought|thoughts|considered|considering|planning|planned|plan|imagining|"
      r"imagined|picturing|pictured|tempted|urge)( about| of| to)? ("
      r"jumping (off|from) (a |the |that |this |my )?(bridge|building|roof|rooftop|cliff|balcony|ledge|tower|car park|"
      r"multi-?storey|window|overpass|motorway bridge)|"
      r"throwing myself (off|from|in front of|under|into (a |the )?(river|sea|lake|traffic|the path of))|"
      r"driving (off|into) (a |the )?(cliff|bridge|wall|tree|river|lake|sea|canal|reservoir|quarry|harbour|harbor|loch|oncoming)\b(?!\s+(district|side|front|view|"
      r"shore|road|town|cafe|park))|"
      r"crashing (my|the) car on purpose|"
      r"walking (into|in front of) (the )?(traffic|a (car|bus|lorry|truck|train))\b|"
      r"stepping in front of (a |the )?(train|bus|car|lorry|truck)|lying (down )?on the (train |railway )?tracks|"
      r"hanging myself|drowning myself|shooting myself|gassing myself|slitting (my )?(wrists?|throat)|"
      r"taking (all( of)?|too many( of)?|a load of|a bunch of|every one of) (my |the |those )?(pills|tablets)\b"
      r"(?!\s+(in the|at|with|as|on|every|each|instead|before|after|for|today|tonight|this)\b))|"
      r"\b(bridge|cliff|roof|rooftop|tracks|railway|ledge|river|lake|woods|forest)s? (seems?|looks?|would be|is) "
      r"(like )?(a |the )?(good|fitting|perfect|right|best) (place|spot) to (die|do it|end it( all)?|end (my life|"
      r"everything|my journey)\b(?! (around|across|through|in|at|on))|finish (it|myself))\b|"
      r"\b(fitting|perfect|good|right|best) (place|spot|way) to end (my life|everything|it all)\b|"
      r"\b(everyone|everybody|people|they|my family|my kids|my children|the world|my (mum|mom|dad|parents|partner|wife|"
      r"husband))\s+(would|'d|will)\s+(be\s+)?(happier|better( off)?|relieved|fine|okay|ok|smile more|be happier)"
      r"[^.!?]{0,25}\bif (I|i) ((were|was) (gone|dead|no longer (here|around|alive))|(wasn.?t|weren.?t|was not|were not) "
      r"(around|alive|here any ?more|in the picture)\b(?! (as much|so much|more|all the time|enough)))"
      r"(?!\s+(for|when|while|during|on|at|this|that|tonight|tomorrow|today|next|over|in the)\b)|"
      r"\b(wish|if only|want|wanted|meant|hope)[^.!?]{0,40}\bnever (wake|waking) up( again)?\s*([.!?,]|$)|"
      r"['\x22“”]?\bcheck(ing)? out['\x22“”]? for good\b|"
      r"\b(time to|going to|want to|wanna|ready to|about to) check out\b(?!\s+(of|the|this|that|a|my|some|these|those|"
      r"at|early|late|now|in|from|our|your|his|her|their)\b)|"
      r"\b(they|everyone|everybody|my family|people|the world|my kids|my children)(\s+(would|will)|'d)\s+(be\s+)?"
      r"(happier|better( off)?|fine) without me\b(?!\s+(for|at|on|this|tonight|tomorrow|today|in|when|while)\b)"),
  // Standard warning signs from suicide-prevention guidance, phrased the many ways people say them.
  'goodbyes and arrangements': _ci(r"(saying|said|say) goodbye to (people|everyone|everybody|friends|my family)(?![^.!?]{0,60}\b(last day|leaving (do|party|drinks|card)|moving|move|new job|retir\w*|holiday|trip|travel\w*|abroad|wedding|graduat\w*|end of (term|year|the year)|at work|desk plants?|colleagues?)\b)(?! (at|after|before) (the|my|our|a|his|her) (party|meeting|airport|station|wedding|funeral|leaving|end|office|school))|"
      r"been saying goodbye|(leave|leaving|left|write|writing) (a |my )?(final )?note (for|to)(?! (myself|remind))|final arrangements|"
      r"arrangements for (when|after) I.?m gone|(giving|gave|give) (my|all my|away my) .{0,25}"
      r"(things|stuff|belongings|possessions|favou?rite)(?!.{0,30}\b(charity|the move|moving|declutter\w*|car boot|ebay|vinted))|\b(i.?m|i am|i)( just| really| probably| honestly)? (not|n.?t) (going to|gonna) be (here|around) "
      r"(next|by|much longer|for (long|much longer)|any ?(more|longer)|tomorrow)(?![^.!?]{0,60}\b(moving|move|holiday|vacation|trip|travel\w*|away|work|busy|exams?|hospital|visiting|abroad|conference|camp|course)\b)"),
  'not existing': _ci(r"tired of (being alive|living(?! (like|this way|in|with|out of|on|off|from|paycheck|alone|at home|together|here|there|apart|abroad))|life(?! (like|being|in|at|with|as|admin|insurance|stuff|things|coaching|lessons)\b))|don.?t want to exist|where I don.?t have to exist|"
      r"(sleep|go to sleep|deep sleep|fall asleep)( \w+)? (forever|and (just )?(never|not) (wake|come back))|"
      r"\bmy life ending|make (the|my) pain stop (for good|permanently|forever)|delete .{0,15}my life|"
      r"go into the light|end (it|everything) (for good|permanently)|"
      r"\bwant (everything|it all|it|life|the world|things|the pain) to (stop|end) (permanently|forever|for good)\b"),
  'unsafe alone': _ci(r"(scared|afraid|worried) of what I (might|could|would) do|"
      r"\bI( a|.?)m (worried|scared) about my (own )?safety\b(?![^.!?]{0,50}\b(walking|driving|cycling|riding|on the way|at work|at night|in the dark|on the (road|roads|street|streets|train|bus|tube)|travel\w*|scaffolding|building site|commute|neighbou?rhood|area|car park|alone at night)\b)|" // "I'm", "Im" and "I am" (verification round 2)
      r"\b(raid|raided|empty|emptied|everything in|all of|go through|went through|going through)( \w+){0,2} (the |my )?medicine cabinet\b|taking something to (sleep|go to sleep|not wake)|"
      r"\b(can.?t|cannot|can no longer|don.?t think i can|unable to) keep myself safe\b|\b(don.?t|do not) feel safe (with|around|from) myself\b|"
      r"\bnot safe (with|from|around) myself\b"),
  'not wanting to live': _ci(r"(don.?t|do not|didn.?t) want to (be alive|be here any ?more|wake up(?! (super |that |so |too |very |this |as )?((early|late|before|with|for (work|school|class|the|my|an?)|in the night|to (go|face|do))\b|at \d|for \d)))|"
      r"(don.?t|do not) want to live(?! (my|like|in|with|this|that|a |the |on|through|alone))|"
      // said of oneself, not of a baby or a son, and not a plain past ("I didn't wake up when my alarm went off": round 6
      // review, F6-06); "I hope I don't wake up" and "I wish I didn't wake up" stay a crisis
      r"\b(i|i.?d|i.?ll|i.?m)( \w+){0,2} (don.?t|won.?t|never|not|wouldn.?t|will not|do not)( ever)? wake up(?! (super |that |so |too |very |this |as )?(early|late|on time|in time|before|at|until|till|feeling|refreshed|rested|anxious|worried|stressed|tired|and miss|with|in the night|once|when|because|for|to|on|during|so)\b)|"
      // "things would be better if I just didn't wake up" (a wish, said as a condition: kept when the plain past went)
      r"\b(better|easier|fine|okay|ok|good|a relief|nicer|simpler)( off)?( \w+){0,4} if i (just |simply )?(didn.?t|did not|never|wouldn.?t|don.?t|do not) (wake|woke) up\b(?! (early|late|on time|in time|with|in the night|when|for)\b)|"
      r"\bif i (just |simply )?(didn.?t|did not|never|don.?t|do not) wake up\b(?! (early|late|on time|in time|with|in the night|when|for)\b)[^.!?]{0,50}\b(fine|better|okay|ok|a relief|good|easier|nicer|simpler|wouldn.?t mind|would not mind)\b|"
      // a wish to have died ("I fell off my bike and I wish it had killed me": round 6, own probe)
      r"\bwish (it|that|they|he|she|the \w+)( had| would have|.d)? (killed|finished) me\b|\bwish i( had|.d)? (died|not survived|never survived)\b(?! (laughing|of (embarrassment|shame|laughter|boredom))\b)|"
      r"\bwish (i|that i) (didn.?t|hadn.?t|wouldn.?t|could never|would never) (wake|woken|waken) up\b(?! (early|late|on time|in time|with|in the night|when|for)\b)|"
      // "I just really wish I was dead": up to two words before "wish" (verification round 2)
      r"(?<!(don.?t|do not|didn.?t|never|wouldn.?t|would never) )want to die\b(?! (of|from|laughing|alone|my|your|his|her|their|the|it|them|this|that)\b)|\bI (\w+ ){0,2}wish I (was|were) dead"),
  // Self-harm said outright: the word itself, cutting an arm or a leg, the wish, the plan or the urge to (2026-11-13:
  // probe reliv-05 "I want to hurt myself" was only a concern), or doing it again and again. No accident exception
  // ever applies to these (security review 2026-11-14, OW-A06-1). The bare "I cut myself" is _cutOrBurnMyself below.
  'self-harm': _ci(r'\bself[- ]?(harm|injur)|\bcut(ting)? (my )?(arms?|wrists?|legs?|thighs?)\b(?! (day|days|workout|workouts|session|training|exercises?|routine|short|hair|sleeves?)\b)|'
      r'\bcutting (helps|calms|relieves|makes me feel)|\b(hit|hitting|punch(ed|ing)?|slap(ped|ping)?) (myself|my own face)\b(?![^.!?]{0,50}\b(cupboard|door|table|shelf|corner|ouch|by accident|accidentally|clumsy|bed ?frame|cabinet|oops)\b)|'
      '\\b(want|wanting|wanted|tempted|planning|urge) to (hurt|harm|cut|burn) $_myself$_notIdiom|'
      '\\b(keep|keeps|kept|been|started|starting|began|begun) (\\w+ )?(cutting|burning) $_myself$_notIdiom'),
  // Asking about a way or a means to die: among the clearest warning signs (2026-11-13: probes means-03 to means-05,
  // which only the classifier caught; checked against the 472,607 CACTUS client lines with tool/safety_scan.dart).
  'method seeking': _ci(r'\b(where|which|what)( is| are|.s)( the)? (highest|tallest) (bridge|building|cliff|car park|tower|multi-?storey)s?\b|\b(highest|tallest) (bridge|building|cliff|car park|tower|multi-?storey)s? (near|around|close to|nearby|to jump|i can (get|reach|access))|\bwhich (bridge|building|cliff|car park|tower|multi-?storey)s? (is|are) (the )?(highest|tallest)\b|'
      r'how long (does|would|will) it take to die|'
      r'\b(die|dying|death) (from|of|by) (carbon monoxide|car exhaust|hanging|an overdose)|'
      r'carbon monoxide.{0,30}\b(die|dying|death|kill)|'
      r'\bcut(ting)? (along|across|down|up) (the|my|your) (arm|wrist)s?|'
      r'\b(along|across) (the|my|your) (arm|wrist)s?.{0,40}(worse|better|deeper|faster|more dangerous)|'
      r'\b(lethal|fatal) dose\b(?! of (caffeine|coffee|espresso|sugar|chocolate|sarcasm|reality|cuteness|nostalgia|work|meetings|tv|telly|netflix)\b)|\bpainless (way|method)s? to (die|go|kill)|'
      r'\b(quickest|easiest|fastest|surest) way to (die|kill (myself|yourself))'),
  'overdose': _ci(r'overdos\w*\b(?! (on|of) (vitamin \w+|iron|salt|sun|chocolate|sugar|caffeine|coffee|cake|sweets|candy|netflix|tv|telly|carbs|junk|pizza|love|cuteness|nostalgia|exercise|work|cheese|food|crisps|biscuits|ice cream|anime|music|podcasts|christmas)\b)|(saving|stockpiling|collecting|hoarding) (up )?(my )?(\w+ )?(pills|tablets)|'
      r'took .{0,30}\b(pills|tablets|xanax|valium|diazepam|lorazepam|codeine|painkillers|paracetamol|tylenol)\b(?!.{0,40}\b(this morning|this (evening|afternoon)|last night|before (bed|sleep)|at (bed ?time|night)|like (always|usual|normal)|as (usual|normal|always)|every (day|night|morning|evening)|and (went|go|going) to (bed|sleep)|and still\b|to (help me )?sleep|like (my|the) (gp|doctor) said|as prescribed|with (breakfast|lunch|dinner|food|water)|on time|late (today|tonight|this)|for (my|a|the) (headache|migraine|pain|period|cramps|back|tooth|cold|flu|fever)|and slept|twice\b))|'
      r'how many .{0,40}(pills|tablets)(?!.{0,30}\b(should i (start|take)|to take|a day|per day|daily|can i (safely )?take))|(pills|tablets).{0,30}(take|taking).{0,12}with .{0,15}'
      r'(whisky|whiskey|alcohol|wine|beer|vodka|drink)'),
  'warning signs': _ci(r'\bI (gave|have given|am giving|.m giving) away ((all|most|everything|all of|most of)( (my|of my))?|my (things|stuff|belongings|possessions|prized|favou?rite|treasured|valuables|savings|money|pets?|cat|dog|collection|books|clothes|jewel\w*))(?!.{0,40}\b(charity|the move|moving|declutter\w*|car boot|ebay|vinted))|'
      r'\bgave away ((all|most|everything|all of|most of)( (my|of my))?|my (things|stuff|belongings|possessions|prized|favou?rite|treasured|valuables|savings|money|pets?|cat|dog|collection|books|clothes|jewel\w*))(?!.{0,40}\b(charity|the move|moving|declutter\w*|car boot|ebay|vinted))|affairs in order|tidying up my affairs|'
      r'(wrote|written|writing) .{0,20}(letters?|notes?)(?! (to|for) (my |the )?(landlord|school|teacher|boss|council|bank|gp|flatmate|roommate|neighbou?r))\b.{0,40}just in case|goodbye (letters?|notes?)(?! (to|for) (the|my|our) (team|colleagues|class|office|staff|students|co-?workers|neighbou?rs|teachers?|boss|school|club|group|leavers?)\b)(?![^.!?]{0,40}\blast day\b)|'
      r"\bI (won.?t|will not) be (around|here) (much longer|for long|any ?more)"),
  // ignore: prefer_interpolation_to_compose_strings (a raw string cannot interpolate: "$_notAtHome" inside it is text)
  'violence at home': _ci(r"\b(he|she|my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|"
      r"brother|sister|son|daughter|ex|step(dad|father|mum|mom|mother|brother|sister)|uncle|aunt|auntie|"
      r"grand(dad|pa|father|ma|mother)|cousin|carer|foster (dad|mum|mom|parent|father|mother)|(mum|mom|dad).?s "
      r"(boyfriend|girlfriend|partner))) (hit|hits|beat|beats|chokes?|choked|kicked|kicks|slapped|slaps) me\b" + _notAtHome + r"|"
      r"(don.?t|do not|not) feel safe at home\b(?![^.!?]{0,60}\b(burglar\w*|break-?in|broken into|robbe\w*|mou?ld|damp|rats?|mice|leak\w*|landlord|neighbou?rhood|area|street|crime|fire|gas|boiler|wiring|storm|flood\w*|ceiling|roof)\b)|"
      r"(afraid|scared) (he|she).{0,20}(kill|hurt) me"),
  'harm to others': _ci(r'(want|going|planning|thinking about) to (kill|attack|stab|beat up) (him|her|them|someone)|'
      r'(make|making) (him|her|them) pay'),
  'suicide+': _ci(r"""\bunaliv(e|es|ed|ing)\b|(?<![\d.,] ?)(\b(i|i.?m|im|gonna|wanna|want to|going to|might|will|about to|just|literally|fr|lowkey|ngl)( \w+)? kms\b|\bkms\s*(fr|rn|lol|tbh|ngl|tonight|now|today)\b)|\bkill?(ing)? (meself|my ?slef|mysef|mself)\b|\bkil+ (my ?self|meself|mysef)\b|\b(going to|gonna|want to|wanna|might|i.?ll|will) off myself\b|\btaking my (own )?life\b(?! (back|into|in (a|an|my|both|new|the|this|that)|seriously|more seriously|for granted|one day|step|easy|easier|slowly))|(\b(wanna|gonna)( just)?|\babout to) end it( all)?\b(?! (tonight|today|tomorrow|now|soon|for good) with (?!(pills?|tablets?|a|an|the|some|drink|alcohol)\b))(?! with (?!(pills?|tablets?|a|an|the|some|drink|alcohol|vodka|whisky|it|my (car|belt|meds|medication|pills|tablets|gun|razor))\b)\w+)(?! with (him|her|them|you|someone|somebody|my (boy|girl)friend|my partner|my (husband|wife|fianc[eé]e?|ex)|that (guy|girl|man|woman|person))\b)(?! (on a (high|good|positive) note|here for|for (today|now|the day)|early))|\bi.?m( just)? ending it( all)?\b(?! (tonight|today|tomorrow|now|soon|for good) with (?!(pills?|tablets?|a|an|the|some|drink|alcohol)\b))(?! with (?!(pills?|tablets?|a|an|the|some|drink|alcohol|vodka|whisky|it|my (car|belt|meds|medication|pills|tablets|gun|razor))\b)\w+)(?! with (him|her|them|you|someone|somebody|my (boy|girl)friend|my partner|my (husband|wife|fianc[eé]e?|ex)|that (guy|girl|man|woman|person))\b)(?! (on a (high|good|positive) note|here for|for (today|now|the day)|early))|\bending it all\b(?! with)"""),
  'not wanting to live+': _ci(r"""(?<!(don.?t|do not|didn.?t|never) )\b(wanna|want 2|wan2|ready to) die\b(?! (of|from|laughing|alone|for|my|your|his|her|their|the|it|them|this|that)\b)|\b(don.?t|do not|didn.?t|dont) (wanna|want 2) (be alive|live any ?more|be here any ?more|wake up)\b|\bbetter off dead\b|(?<!\b(not that i|it.?s not that i|doesn.?t mean i|don.?t|do not|didn.?t|never|not because i) )\bwant(ed)? to be dead\b|(^|[.!?;:]\s*)(\w+,? )?wish (i|i.?d) (was|were|had been|could be) dead\b|\b(want(ing)?|wanna|wish i could|need) (to )?(stop existing|not exist|cease to exist|stop being alive)\b(?! for (a |the )?(bit|while|moment|second|minute|day|few|weekend|night|week))|\b(nobody|no one|no-one) (would|will|is going to|gonna)( even)? (miss|notice|care)( about)?( me)? (if|when) i (was|were|.?m|am) (gone|dead|not here)\b(?! (for|from|to)\b)|\bwant (it all|everything|my life) to (end|be over)\b(?! (well|happily|soon|on|so|by|before|after|in|this|next|already)\b)"""),
  'method ideation+': _ci(r"""\b(want|wanted|wanna|going|gonna|will|i.?ll|ready|about|decided|need|try(ing)?|plan(ning)?|tempted|urge)( to)?( just)? ((hang|drown|shoot|gas|electrocute) myself\b(?! (in the foot|out to dry|in (my )?(work|coffee|tea|wine|books?|study|studying|tasks|chores|paperwork|music|tv|netflix|chocolate|food|sorrows|projects?|a ?bit)))|(jump|throw myself) (off|from|in front of|under) (a |the |that |this |my )?(bridge|building|roof|rooftop|cliff|balcony|ledge|tower|car park|multi-?storey|window|overpass|train|bus|lorry|truck|car|tube)\b|slit (my )?(wrists?|throat)|(walk|step) (into|in front of) (the )?(traffic|a (car|bus|lorry|truck|train))\b|drive (my car )?(off|into) (a |the )?(cliff|bridge|wall|tree|river|lake|sea|canal|reservoir|quarry|harbour|harbor|loch|oncoming)\b(?!\s+(district|side|front|view|shore|road|town|cafe|park))|lie (down )?on the (train |railway )?tracks)|\b(tied|tying|tie|bought|made|making|got) (a |the |my )?noose\b"""),
  'overdose+': _ci(r"""\b(taken|swallowed|downed|necked|took|had|eaten|ate)( \w+)? (all|every|\d{2,}|twenty|thirty|forty|fifty|a hundred|a (whole|full) (bottle|packet|box|strip|pack|tub)|(a )?(load|bunch|handful|lot|bottle|packet|box|pack|tub|strip)s? of|loads of|everything in)\b.{0,30}?\b(pills|tablets|meds|medication|medicine|paracetamol|acetaminophen|tylenol|ibuprofen|aspirin|codeine|insulin|sertraline|citalopram|fluoxetine|amitriptyline|antidepressants|sleeping pills|xanax|valium|diazepam|lorazepam|drawer|cabinet)\b(?!.{0,25}\b(as prescribed|on time|today|this morning|like (i.?m|i was) (told|supposed)|for the (week|day)))|\bhow (many|much) .{0,40}\b(pills|tablets|meds|medication|medicine|paracetamol|acetaminophen|tylenol|ibuprofen|aspirin|codeine|insulin|sertraline|citalopram|fluoxetine|amitriptyline|antidepressants|sleeping pills|xanax|valium|diazepam|lorazepam)\b.{0,40}\b(kill|die|dead|fatal|lethal|(would|does|will) it take|it takes|enough to|not wake|never wake|overdose|to end)|(saving|stockpiling|collecting|hoarding) (up )?(my )?(\w+ )?(meds|medication|prescriptions?|antidepressants|painkillers|sleeping pills|paracetamol|codeine|tramadol|insulin|sertraline|citalopram|fluoxetine|amitriptyline|mirtazapine|zopiclone|diazepam|lorazepam|oxycodone|morphine)\b(?! (receipts?|money|costs?|bills?|forms?|list|boxes|bags)\b)"""),
  'warning signs+': _ci(r"""\b(wrote|written|writing|finished|left|leaving) my (final |last |goodbye |suicide )?note\s*([.!]|$)|\bI (won.?t|will not|wont) be (here|around|alive) (tomorrow|by (tomorrow|morning|the weekend))\s*([.!]|$)|\bI.?ll be dead (by|before) """),
  'self-harm+': _ci(r"""\bI(.?ve| have|.?m| am)?( been| started| keep| kept| relapsed and| began)? (cutting|cut|burning|burned|burnt)( myself)? again\b|\bcut(ting)? (my )?(stomach|belly|hips?|ribs?|chest|forearms?|ankles?|calves)\b|\bburn(ed|t|ing)? (my )?(arms?|wrists?|legs?|thighs?|skin|stomach|hands?)\b.{0,25}\b(lighter|cigarettes?|matches)\b|\b(urges?|craving|need|want|wanting) to (cut|self.?harm|sh)\b(?! (back|down|it|the|this|that|my hair|myself|corners|ties|out|off|up|class|school|sugar|carbs|costs|people|them|him|her|loose|in|through|across|away|bread|cake|meat|grass|a |an |my (arm|leg|chest|back|ab|abs|upper body|lower body) (day|workout|session|training|routine)|my (workout|training|session|losses|spending|hours|nails|toenails|fringe)))|\bcarv(e|ed|ing)\b.{0,30}\b(into|in|on) my (arm|leg|thigh|wrist|skin|stomach)|\b(relaps\w* (on|with)|urges? to|clean from) (sh|s/h)\b|\bsh'?ing\b"""),
  'harm to others+': _ci(r"""(?<!\b(don.?t|do not|didn.?t|never|not|won.?t|wouldn.?t|scared|afraid|worried|worry|fear|thinks?|probably|might)( \S+){0,3} )\b(want|wanna|going|gonna|planning|plan|ready|about|decided|i.?ll)( to)? (kill|attack|stab|shoot|strangle|hurt|beat up|murder|poison|drown|smother|suffocate) (him|her|them|someone|somebody|everyone|people|them all|my (boss|husband|wife|partner|dad|mum|mom|father|mother|brother|sister|ex|neighbou?r|teacher|kids?|children|son|daughter|baby|manager|colleague|roommate|flatmate|stepdad|stepmum|family|classmates?)|the (kids|children|baby|class|students))\b(?! (feelings|chances|career|reputation|pride|ego))(?<!\bhurt (someone|somebody|everyone|people))|\b(thinking|fantasi[sz]ing|dreaming) about (killing|attacking|stabbing|shooting|strangling|hurting|murdering|poisoning) (him|her|them|someone|somebody|everyone|people|them all|my (boss|husband|wife|partner|dad|mum|mom|father|mother|brother|sister|ex|neighbou?r|teacher|kids?|children|son|daughter|baby|manager|colleague|roommate|flatmate|stepdad|stepmum|family|classmates?)|the (kids|children|baby|class|students))\b(?! (feelings|chances|career|reputation|pride|ego))|\bshoot up (my|the|a) (school|work|office|church|mosque|synagogue|mall|class)\b|\b(bring|bringing|take|taking|brought) (a|my|the) (knife|gun|weapon|rifle|pistol) (to|into) (school|work|class|the office)\b"""),
  'violence at home+': _ci(r"""\b(he|she|my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|brother|sister|son|daughter|ex|stepdad|stepfather|stepmum|stepmother|uncle))( \w+)? (strangled|strangles|punched|punches|raped|rapes|shoved|threatened to (kill|hurt)|pushed me (down|into|against|off|over))( me)?\b(?![^.!?]{0,40}\b(for winning|after (winning|losing)|as a joke|jokingly|playful\w*|play fight\w*|in (her|his|their) sleep|by accident|accidentally|at (fifa|chess|tennis|football))\b)|\b(raped|molested|sexually assaulted) me\b|\b(i.?m|i am) being (abused|beaten|hit) (at home|by)\b"""),
  'extra+': _ci(r"""\bvoices?\b.{0,40}\b(tell|telling|told|want|wants|wanted|say|saying|says|said|order\w*|command\w*)( me)? (to|that i should|i should|i must|i need to|i have to) (hurt|kill|harm|cut|end|stab|burn|hang|drown|poison|starve|shoot) (myself|me|my life|it all|him|her|them|someone|people|my (kids|children|child|baby|babies|son|daughter|family|partner|wife|husband|mum|mom|dad)|the (kids|children|baby))\b|\bvoices?\b.{0,40}\b(tell|telling|told|want|wants|wanted|say|saying|says|said|order\w*|command\w*)( me)? (to|that i should|i should|i must|i need to|i have to) (jump|die|overdose)\b(?! (at|on|in|into|ship|through|the gun|ahead|right|of laughing)\b)|\bvoices?\b.{0,40}\b(tell|telling|told|say|saying|says)( me)? (to die|i should die|i deserve to die)\b|\bworth more dead\b|\bdeath (would be|will be|feels like|sounds like|seems like) (a |the )?(relief|release|welcome|easier|better|answer|only way)\b|\b(pills|tablets)\b.{0,15}\b(lined up|counted out|laid out|in front of me)\b|\b(would|'d|will) be (happier|better( off)?|fine|relieved)[^.!?]{0,25}\bif i (wasn.?t|weren.?t|was not|were not) here\b(?! (for|when|while|on|at|this|that|tonight|tomorrow|today|next|over|in|to)\b)|\bif i (disappeared|died|vanished|was gone|were gone) (for good|forever|permanently)\b"""),
  // Round 4 review (B-01, B-02, B-03): explicit ways, means, places, times and farewells that reached neither the rules
  // nor the classifier once the therapist had spoken (the classifier reads each message with her last words, and after
  // an ordinary greeting it scored "I'm going to put a gun to my head" 0.48). Each rule needs a concrete means, place,
  // time or a plain farewell, never a feeling alone, and none can be denied or put in the past: the classifier reads
  // the rest. Checked against the 472,607 CACTUS client lines with tool/safety_scan.dart.
  'means and plans': _ci(r"""\b(going to|gonna|want to|wanna|about to|ready to|decided to|planning to|plan to|need to|"""
      r"""i.?ll|i will|i shall|tempted to|thinking (about|of)|think about|urge to|trying to|try to)( just| finally| actually| really)? ("""
      r"""(put|putting|hold|holding|press|pressing|stick|sticking) (a |the |my |his |her |\w+'s )?(gun|pistol|revolver|rifle|shotgun|handgun|barrel) (to|against|in|into) my (head|temple|mouth|chin)|"""
      r"""(blow|blowing) my (own )?brains out|(put|putting|fire|firing|shoot|shooting) a bullet (in|into|through) my (head|brain|skull|heart)|"""
      r"""(drink|drinking|swallow|swallowing|take|taking|down|downing) (some |the |a (bottle|cup|glass|can) of )?(bleach|antifreeze|weed ?killer|rat poison|poison|drain cleaner|pesticide|paraquat)\b|"""
      r"""(set|setting) (myself|me) (on fire|alight|ablaze)|(set|setting) fire to myself|(burn|burning) myself (alive|to death)|"""
      r"""(put|putting|tie|tying|pull|pulling) (a |the )?(plastic )?bag over my (head|face)|(put|putting|stick|sticking) my head in (the |a )?(gas )?oven|"""
      r"""(run|running|leave|leaving|start|starting|sit|sitting in) (the|my) (car|engine)( running)? in (the|a|my) (closed |shut |locked )?garage|"""
      r"""(slash|slashing|slice|slicing|open|opening)( up)? my (wrists?|throat|veins)|(cut|cutting|slit|slitting) my (own )?throat|"""
      r"""(jump|jumping) (off|from) (something|somewhere|anything) (high|tall)|(jump|jumping)\s*([.!?]|$)(?![\s\S]{0,100}\b(parachute|skydiv\w*|bungee|plane|aircraft|pool|lake|trampoline|queue|ski|instructor|zip ?line|diving board|tandem|swim\w*)\b)|"""
      r"""(swallow|swallowing|take|taking|down|downing|neck|necking) (every |all (of )?(the |my |those |my \w+'s |\w+'s )?(sleeping |sleep |pain ?|heart |blood pressure |anxiety )?)(pill|tablet|pills|tablets|meds|medication)s?\b(?! (as|like) (prescribed|i.?m (told|supposed)))(?!\s+(in the (morning|evening|afternoon)|at (once|breakfast|lunch|dinner|bedtime|night|the same time)|with (food|water|breakfast|lunch|dinner|meals?)|as (one|a single)|on time|every|each|instead|before (bed|breakfast|food)|after (breakfast|lunch|dinner|meals?|food|eating)|for (my|the|this) (week|day|headache|pain|infection|cold|flu))\b)|"""
      r"""(top|topping) myself|(do|doing) myself in\b|(end|ending) myself|(starve|starving) myself (to death|until i die|till i die)|"""
      // round 5 review (D-01, D-02): a cupboard or a whole box of tablets, a platform, the sea, a canal
      r"""(swallow|swallowing|take|taking|down|downing|neck|necking|overdose on) (everything|all|the lot|whatever.?s|what.?s) (in|from) (the |my |our )?(medicine (cupboard|cabinet|drawer|box|chest)|bathroom cabinet|first aid (kit|box)|pill (box|drawer))|"""
      r"""(take|taking|swallow|swallowing|down|downing|neck|necking) (the |a |my )?(whole|entire|full) (box|bottle|packet|pack|strip|tub|jar|blister)s? of\b|"""
      r"""(step|stepping|jump|jumping|throw myself|walk|walking) (off|from|onto|in front of) (the )?(edge of the )?(platform|tracks|railway line)\b|"""
      r"""(walk|walking) into the (sea|ocean|river|lake|loch|water|waves)(\s*([.!]|$)| and (keep walking|keep going|not come back|never come back|drown|disappear|let it take me)| until)|"""
      r"""(die|be dead|kill myself|end it( all)?|end my life) (tonight|tomorrow|this (weekend|week)|by (tomorrow|morning|the weekend|friday|saturday|sunday))\b)|"""
      r"""\b(going to|gonna|will|i.?ll) be dead (by|before) (tomorrow|tonight|morning|the (weekend|end of (the|this) (day|week)))|"""
      r"""\b(this is|it.?s|tonight is|today is) my (very )?last (night|day) (alive|on (this )?earth)\b|"""
      r"""\b(tonight|today|now),? i jump\b|\bi.?m (on|at|standing on|sitting on) (the|a) (ledge|edge|railing|parapet)\b[^.!?]{0,40}\bjump|"""
      r"""(?<!\b(like|as if|as though|feels?|feeling|felt) )\bi.?m (sitting|standing|stood|sat|perched) on (the )?(edge of (the|a|this) (bridge|roof|rooftop|building|cliff|balcony|car park)|(a|the|this) (ledge|railing|parapet))\b(?! (path|walk|top|road|trail|cafe|steps)\b)(?![^.!?]{0,60}\b(photos?|pictures?|selfies?|view|walk\w*|hik\w*|sunset|sunrise)\b)|"""
      r"""\bi (need|have|got) to die\b(?! (some ?day|one day|eventually|sometime|of|from|at some point|to|for)\b)|"""
      r"""\b(i.?d|i would) rather (be dead|die)\s*([.!]|$)|\bplanning my (own )?(death|suicide)\b|"""
      r"""\b(tied|tying|tie|hung|hanging|fixed|attached) (a |the |my )?(rope|noose|belt|cord) (to|from|over|round|around) (?![^.!?]{0,80}\b(punch ?bag|swing|hammock|pulley|plants?|lights|decorations|tarp|tent|bike|kayak|boat|washing|clothes)\b)(the |a |my )?(beam|rafter|ceiling|banister|bannister|loft hatch|hook|door ?handle|doorknob|door frame|top of the door|wardrobe rail|curtain rail|clothes rail|bedpost|pipe)\b|"""
      r"""\b(got|have|bought|sorted|prepared)( \w+){0,2} (the |a |my )?(rope|noose|gun|pistol|shotgun|rifle)\b[^.!?]{0,20}\b(ready|for tonight|tonight)\b(?! for (the |a |my |our )?(climbing|camping|sailing|hiking|boat|tent|swing|move|trip|holiday|bouldering|abseiling))|"""
      r"""\bi.?(ve| have)? (picked|chosen|chose|set) (a |the |my )?date\s*([.!]|$)|"""
      r"""\b(picked|chosen|chose|set|decided on|planned) (a|the|my) (date|day|time) (to die|to do it|to end it( all)?|to kill myself|for my death)\b|"""
      r"""\b(nobody|no one|no-one) will (ever )?see me again (after|by|from) (tonight|today|tomorrow|this)\b|"""
      // round 5 review (D-01, D-02): a place and not coming back; a car and its engine in a garage; a blade held to a
      // wrist; a body part burned or cut on purpose; a decision to die; up high right now; gone before morning
      r"""\b(bridge|cliff|tracks|railway|river|sea|lake|woods|forest|roof|rooftop|edge|car park|motorway|quarry|canal)\b[^.!?]{0,60}\b(not|never) coming (back|home|down)\b|"""
      // round 6 review (F6-08): a car running in a shut garage, said plainly; an attempt and the next one; a relapse of
      // self-harm; not being able to keep oneself safe; a firearm and when
      r"""\bin (the|my) car with the engine (running|on)\b[^.!?]{0,60}\bgarage\b|\bgarage (door )?(is )?(shut|closed|locked)\b[^.!?]{0,60}\bengine (is )?(running|on)\b|"""
      r"""\b(i|i.?ve) attempted (last|this|yesterday|recently|before|a (few )?(days?|weeks?|months?) ago)\b[^.!?]{0,80}\b(try|do it|attempt) again\b|"""
      r"""\brelapsed (on|with|into|and started) (cutting|self[- ]?harm\w*|burning( myself)?)\b|"""
      // round 7 review, H7-06: an attempt and the next one, said with a season; standing at a height thinking of going over;
      // sexual abuse told as a family member or carer coming to the person's room or bed and touching them
      r"""\b(he|she|my (dad|father|stepdad|stepfather|mum|mom|mother|stepmum|stepmother|brother|stepbrother|uncle|cousin|grandad|grandpa|grandfather|carer|foster (dad|father|parent)|(mum|mom).?s (boyfriend|partner)))( \w+){0,6} (comes?|came|coming|gets?|got) (into|in) (my|the) (room|bed|bedroom)\b[^.!?]{0,60}\b(touch\w*|grope\w*|feel\w* me up|molest\w*)\b|"""
      r"""\b(i|i.?ve) attempted (in|over|during|last|this) (the )?(summer|spring|autumn|fall|winter|holidays?|year|month|week)\b[^.!?]{0,80}\b(try|do it|attempt) again\b|"""
      r"""\b(stood|standing|sat|sitting) on (the|a) (bridge|ledge|roof|rooftop|edge of the cliff|cliff edge|platform edge)\b[^.!?]{0,80}\b(thinking (about|of)|wanting to|ready to|about to) (going over|jumping|falling|stepping off|letting go)\b|"""
      r"""\b(plan|planning|going|want|ready|decided)( \w+)? to use (the |my |a |his |her |\w+'s )?(rifle|gun|shotgun|pistol|revolver|handgun|rope|noose)\b[^.!?]{0,60}\b(do it|end it|on myself|tonight|this (evening|afternoon|weekend)|alone|when (they|everyone)( are|.re) (out|asleep|gone))\b|"""
      r"""\b(not|never) coming (back|home) (after|from) (tonight|today|this)\b|"""
      r"""\b(sitting|sat|sit) in (the|my) car\b[^.!?]{0,40}\bengine (running|on)\b[^.!?]{0,40}\bgarage\b|\b(sitting|sat|sit) in (the|my) car in the (closed |shut |locked )?garage\b[^.!?]{0,30}\bengine (running|on)\b|\bhose\b[^.!?]{0,30}\bexhaust\b|"""
      r"""\b(hold|holding|held|press|pressing|pressed|put|putting)( \w+)? (a |the |my )?(knife|blade|razor|scissors|shard|piece of glass) (against|to|on|into) my (wrists?|throat|neck|arms?|skin|thighs?)\b|"""
      r"""\b(burn|burned|burnt|burning|cut|cutting|slashed|slashing) my (arms?|wrists?|legs?|thighs?|hands?|skin|stomach|body|chest|face|hips?)\b[^.!?]{0,40}\b(on purpose|deliberately|intentionally|to (feel|punish|cope|calm|numb|stop))\b|"""
      r"""\btook a (razor|blade|knife|lighter|cigarette|compass) to my (arms?|wrists?|legs?|thighs?|skin|stomach|body|hips?|chest)\b|"""
      r"""\bi( have|.?ve)? (decided|made up my mind) to (die|kill myself|end (it|my life|everything)|go through with it)\b|"""
      r"""\b(i.?m|i am) (at|on) the (very )?top (floor )?of (the|a) (multi-?storey|car park|building|tower|block|bridge|cliff|flats)\b[^.!?]{0,30}\b(now|right now|tonight)\b|"""
      r"""\bi.?ll be gone (by|before) (the )?(morning|tomorrow)\s*([.!]|$)|"""
      // "do it tonight" (never "do it this weekend", which is homework: CACTUS, round 4)
      r"""\b(going to|gonna|i.?ll|i will|plan(ning)? to|ready to|about to) do it (tonight|tomorrow night|when (the kids are|everyone is|everyone.?s|they are|they.?re|he is|he.?s|she is|she.?s) asleep)\b(?![^.!?]{0,80}\b(tax return|tax|homework|laundry|washing|ironing|cleaning|tidy\w*|emails?|admin|paperwork|exercise|workout|yoga|presents?|wrapping|cake|baking|assignment|essay|report|marking|accounts|invoices?|budget|bills?|finally sort|sort out|watch|film|movie|game|bath)\b)"""),
  'farewells': _ci(r"""\bgoodbye forever\b|\bthis (will be|is) my (very )?(last|final) (message|note|post)\b|\b(this is|it.?s) (my )?(final |last )?goodbye\b(?!\s*(for now|until|till|,? see you|to (?!(everyone|everybody|you|you all|all of you|the world|this world|this life|my life|life|it all|my (family|kids|children|friends|mum|mom|dad|parents|partner|wife|husband))\b)))|"""
      r"""\bsaying my (final |last )goodbyes\b|\bsaying my goodbyes (tonight|now|today)\s*([.!]|$)"""),
  // "end it with" a drug, a long gun or any means after "my <someone>'s" (B-02: the break-up exception above lets any
  // single word after "with" mean a person, so "end it with paracetamol" or "with my dad's shotgun" was silenced)
  'ending it with means': _ci(r"""\b(going to|gonna|want to|wanna|ready to|about to|decided to|planning to|plan to|need to|i.?ll|i will)( just)? end(ing)? it( all)?( tonight| today| now| soon| for good| this (week|weekend))? (with|using|by taking) ((a|an|the|some|all|of|my|his|her|their|those|these|\w+'s)\s+){0,4}"""
      r"""(pills?|tablets?|meds|medication|medicine|paracetamol|acetaminophen|tylenol|ibuprofen|aspirin|codeine|insulin|heroin|fentanyl|morphine|methadone|oxycodone|oxycontin|opioids?|opiates?|painkillers|sleeping pills|antidepressants|sertraline|citalopram|fluoxetine|amitriptyline|xanax|valium|diazepam|lorazepam|"""
      r"""gun|shotgun|rifle|pistol|revolver|handgun|firearm|bullets?|rope|noose|belt|knife|blade|razor|bleach|poison|antifreeze|exhaust|carbon monoxide|helium|plastic bag)\b"""),
  // someone's suicide, then the person's own intent to follow (B-02: the bereavement exception read only the noun)
  'following someone': _ci(r"""\b(suicide|killed (him|her|them)sel(f|ves)|took (his|her|their) (own )?li(fe|ves)|hanged (him|her|them)self|overdosed)\b.{0,160}?\b(i.?m|i am|i.?ll|i will|i want|i wanna|going|gonna|want|wanna|planning|ready|thinking (about|of))( to)? (do(ing)? the same|join(ing)? (him|her|them)|follow(ing)? (him|her|them)|go(ing)? the same way|mine|my own|be next)\b"""),
  // self-injury said in the present in other words (B-02: "used to self-harm ... Now I just punch walls till my
  // knuckles bleed" was set aside as past)
  // "I'm hitting a wall" (stuck) stays quiet: punching, banging or smashing, or hitting with the head, fists or hands,
  // and an injury (CACTUS)
  'self-injury': _ci(r"""\b((punch|punching|punched|bang|banging|banged|smash|smashing|smashed)( my (head|fists?|hands?))?|(hit|hitting) my (head|fists?|hands?)) (against |into |on )?(the |a )?walls?\b[^.!?]{0,40}\b(bleed|bleeds|bled|bleeding|bruis\w*|split|broke (my|a)|break (my|a)|crack\w*)\b"""),
  // threats and fear of being killed at home (B-03); "my mum will kill me if I'm late" stays quiet ("if", "unless")
  'threats at home': _ci(r"""\b(he|she|they|my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|brother|ex|stepdad|stepfather|stepmum|stepmother|uncle|carer))( \w+)? (put|puts|had|wrapped|squeezed|pressed|grabbed|held) (his|her|their|both) (hands?|arms?|fingers) (around|round|on|over) my (neck|throat)\b|\b(he|she|they|my \w+)( \w+)? (put|wrapped|tied|pulled) (a |the )?(cord|belt|rope|scarf|wire) (around|round) my neck\b|\bkill (me|us)( and (the|my|our) (kids|children|baby|son|daughter))? if i (ever )?(leave|left|try to leave|tell|told|call|called|report|go to the police|go to anyone)\b|\bif i (ever )?(leave|try to leave|tell anyone|call the police|go to the police|report (him|her))\b[^.!?]{0,40}\b(he|she|they).?(ll| will| would| is going to| said he.?d| said she.?d)( \w+)? kill (me|us)\b|\b(locks?|locked|keeps? locking) me (in|inside|up)\b[^.!?]{0,60}\b(kill|hurt) me\b|\b(touch|touching|touched|touches) me (sexually|inappropriately)\b|\b(sexually|inappropriately) (touch|touching|touched|touches) me\b|\b(he|she|my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|brother|sister|son|daughter|ex|step(dad|father|mum|mom|mother|brother|sister)|uncle|aunt|auntie|grand(dad|pa|father|ma|mother)|cousin|carer|foster (dad|mum|mom|parent|father|mother)|(mum|mom|dad).?s (boyfriend|girlfriend|partner)|flatmate|roommate|landlord))( \w+)? (has|had|got|is holding|was holding|pulled|grabbed|picked up) (a |the |his |her |their )?(knife|gun|weapon|blade|rifle|shotgun)\b[^.!?]{0,60}\b(kill|stab|shoot|hurt) me\b|"""
      r"""\b(he|she|my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|brother|sister|son|daughter|ex|step(dad|father|mum|mom|mother|brother|sister)|uncle|aunt|auntie|grand(dad|pa|father|ma|mother)|cousin|carer|flatmate|roommate|landlord))( \w+)? (said|says|told me|swore|is saying|keeps saying|keeps telling me|screamed|shouted) (that )?(he|she).?(s| is| will|.?ll| was| would)( going to| gonna)? (kill|stab|shoot|strangle) me\b(?!\s+(if|unless|when i)\b)|"""
      r"""\b(scared|afraid|terrified|frightened)( that)? (my (husband|wife|partner|boyfriend|girlfriend|dad|father|mum|mom|mother|brother|sister|son|ex|step(dad|father|mum|mom|mother|brother)|uncle|carer|flatmate|roommate|landlord))( \w+)? (will|.?ll|is going to|.?s going to|might|would|could) (actually |really |literally )?(kill|seriously hurt) me\b(?!\s+(if|unless|when i)\b)|"""
      // "He's going to kill me tonight." said as the whole sentence; "she's going to kill me when she sees the bill" stays quiet
      r"""\b(he|she|my (husband|wife|partner|boyfriend|girlfriend|dad|father|stepdad|stepfather|ex)).?(s| is) (going to|gonna) kill me (tonight|when (he|she) gets (home|back|in))\s*([.!]|$)"""),
};

// A capitalised name doing the hitting ("Faris hit me"), but not "It hit me" or "Then it hit me".
// Hit or beaten in a game, a sport or play is not violence at home (round 6 review, F6-06: "She beat me at tennis", "He hit
// me with a snowball"); shared by both violence rules so they never drift apart.
const _notAtHome = r'(?! up\b| with (a |the |his |her |their )?(pillow|bill|news|idea|question|request|joke|truth|fact|'
    r'snowball|ball|cushion|water balloon|balloon|frisbee)\b| at (tennis|chess|cards|poker|football|golf|squash|'
    r'badminton|pool|snooker|darts|scrabble|monopoly|board games|games|every|anything|everything|running|swimming|maths|'
    r'math|\w+ ?(game|games|match|matches|race|races))\b| (in|to) (the|a|every) (race|game|match|final|vote|finish)\b|'
    // round 7 review, H7-01: in her sleep, in play
    r'[^.!?]{0,30}\b(in (her|his|their) sleep|for winning|after (winning|losing)|as a joke|jokingly|playful\w*|play fight\w*|by accident|accidentally)\b)';

final _namedViolence = RegExp(
    // ignore: prefer_interpolation_to_compose_strings (a raw string cannot interpolate: "$_notAtHome" inside it is text)
    r"\b(?!(It|This|That|They|Those|These|Thoughts|Words|Memories|Life|Reality|Everything|Then|Suddenly|Which|What)\b)[A-Z][a-z]+ "
    r"(hit|hits|beat|beats|choked|chokes|kicked|slapped) me\b" + _notAtHome);

// The bare "I cut myself" or "I burned myself" (crisis) and "I hurt myself" (concern). An accident is not self-harm
// ("I cut myself shaving", "I burned myself on the oven", "I'm scared I'll fall and hurt myself"), but the exception is
// narrow (security review 2026-11-14, OW-A06-1: it used to look at the whole message, so "I want to cut myself with a
// knife" or "I've been self-harming since I stopped eating" opened nothing). It applies only to these bare forms, never
// to the explicit ones above; only when a word for how an accident happens stands within five words, in the same
// clause; and never when the clause says it was meant ("on purpose", "it wasn't an accident", "to feel something").
// Knives, the kitchen, food, eating, diet, health and illness are not accident words: they come up with self-harm.
final _cutOrBurnMyself = _ci('\\b(cut|cutting|burn|burned|burnt|burning) $_myself$_notIdiom');
final _hurtMyself = _ci('\\b(hurt|harm)(ing)? $_myself');
final _accident = _ci(r'\b(fall|falls|falling|fell|fallen)\b(?! (apart|asleep|behind|out|in love|to pieces|ill|sick|'
    r'silent|quiet|into|back into|for)\b)|\b(tripped|tripping|stumbled?|stumbling)\b|'
    // "I might trip", but not a journey ("on my trip")
    r'(?<!\b(a|the|my|our|this|that|your|his|her|their|road|school|camping|business|work|day|weekend|family|field) )'
    r'\btrips?\b|'
    // "I slipped on the ice", but not a relapse ("I had a slip", "I slipped up")
    r'(?<!\b(a|another|one) )\b(slip|slips|slipped|slipping)\b(?![- ]?ups?\b)|'
    r'\b(accidentally|accidental|by accident|an accident|crash|crashed|crashing|ladder|stairs|bike|cycling|ski|skis|'
    r'skiing|skied|skating|skateboard\w*|horse|climbing|hiking|chop|chops|chopped|chopping|peeling|cooking|baking|'
    r'shaving|shaved|oven|stove|hob|kettle|frying pan|saucepan|hot pan|tray|grill|barbecue|bbq|tin|can opener|'
    r'workouts?|gym|sports?|football|rugby|clumsy)\b');
// The clause says it was meant, not an accident.
final _meant = _ci(r"on purpose|\bdeliberate(ly)?\b|\bintentional(ly)?\b|\bpurpose(ly|fully)\b|\bmeant to\b|"
    r"(\bnot|\bno|\bnever|n.t)( \w+){0,2} accident\w*|\bto (feel|cope|punish|calm|numb|forget|stop|release|"
    r"distract|deal)\b|\brelie(f|ve)|\b(calms|calmed|helps|helped) me\b|\bfeels? better\b|\burges?\b");
// For the crisis form ("I cut / burned myself") only: words that say it was meant (verification round 3, R3-2).
// "again" is left out: "I cut myself shaving again this morning" is an everyday accident; the classifier reads the rest.
final _meantCrisis = _ci(r"\bdeserve\w*|\bhate (myself|my ?self|my body|me)\b|"
    r"\bfelt (good|better|calm|right)\b|\b(needed|wanted) to\b|"
    // coping or hiding (round 4 review, B-02): "when I feel numb", "the only place nobody sees", "to feel something"
    r"\bwhen i (feel|felt|get|got) (numb|empty|nothing|bad|low|overwhelmed|angry|sad|upset|anxious|stressed|worthless|"
    r"dead inside)\b|\b(nobody|no one|no-one) (sees|saw|knows|can see|will see|notices)\b|\bonly place\b|"
    r"\bto feel (something|real|alive|anything)\b|\bagain and again\b|\bnight after night\b");
// Intent said in the sentence after the words, or the one after that when the next is short (round 6 review, F6-02: "I
// burned myself on the kettle. I did it on purpose."; "I cut myself shaving. Every morning. It's the only thing that
// helps."). Only plain intent: "I burned myself cooking. I wanted to make pancakes." stays an accident.
final _meantNext = _ci(r"\bon purpose\b|\bdeliberate(ly)?\b|\bintentional(ly)?\b|\bmeant to\b|\bdid it (to )?my ?self\b|"
    r"\b(wasn.?t|was not|not|no|never)( \w+){0,2} (an )?accident\w*|\b(wanted|needed|want|need) to (see|feel|watch|hurt|"
    r"punish|bleed|see the blood|feel (something|the pain|real|alive))\b|\bkept going\b|\b(went|cut|go|going) deeper\b|"
    r"\bdeserve\w*|\bonly (thing|way) that (helps|works|calms)|\b(helps|helped|calms|calmed) me\b|\bto (feel|cope|punish|"
    r"calm|numb|release)\b|\burges?\b|\brelie(f|ve)");
final _wantedNext = _ci(r"\b(really )?want(ed)? to\b(?! (stop (worrying|thinking about it|obsessing|panicking)|relax|feel "
    r"(better|calm|normal)|get (better|help|over)|be (calm|okay|ok|normal)|know|understand|ask))|\bdeserve\w*|\burges?\b|"
    r"\btempted\b|\bon purpose\b|\b(make|makes|made|would make) (it|the pain|everything|the feelings?) stop\b|\bpain stop\b|"
    r"\brelie(f|ve)|\b(bought|got|have|hid|hidden|keep|kept)( \w+)? (new |some |a |my )?(blades?|razors?)\b");

/// The rest of the words' sentence and the next one, or the next two when the next is short ("Every morning."), at most
/// 200 characters (round 6 review, F6-02).
String _andNext(String message, int from) {
  final after = message.substring(from, message.length - from < 200 ? message.length : from + 200);
  var ends = 0, last = 0;
  for (final b in _ends.allMatches(after)) {
    ends++;
    if ((ends == 2 && b.end - last >= 30) || ends == 3) return after.substring(0, b.end);
    last = b.end;
  }
  return after;
}

final _ends = RegExp(r'[.!?;]+');

// For the crisis form only: the accident is the subject, not the cause ("I cut myself when I think about the crash",
// "since my fall", "I remember the accident").
final _accidentAsSubject = _ci(r'\b(remember\w*|memor\w*|flashbacks?|nightmares?|'
    r'(since|after|about|of) (the|my|that|this|our|his|her|their))\b');
// For the crisis form a clause ends at sentence punctuation, a comma, a bracket, a quotation mark, a dash or "but";
// for the concern ("I hurt myself") only at the end of a sentence ("If I fall, I'll hurt myself" stays quiet).
final _clauseBreak = _ci('[.!?;:,()"“”]|\\s[-–—]\\s|\\b(but|though|although|however)\\b');
final _sentenceBreak = RegExp('[.!?;:()"“”]|\\s[-–—]\\s');
final _word = RegExp(r'\S+');

/// True when every match of [form] in [message] is an accident: a word in [_accident] within five words of it, in
/// the same clause (as [breaks] ends one), and nothing in that clause matching one of [meant]. A clause is read at
/// most 160 characters on each side, and a message that mentions it more than 30 times is never all accidents, so a
/// hostile paste costs a few milliseconds here, however long it is.
bool _onlyAccidents(RegExp form, String message, RegExp breaks, List<RegExp> meant) {
  var count = 0;
  for (final m in form.allMatches(message)) {
    if (++count > 30) return false;
    var before = message.substring(m.start < 160 ? 0 : m.start - 160, m.start);
    var after = message.substring(m.end, message.length - m.end < 160 ? message.length : m.end + 160);
    final previous = breaks.allMatches(before);
    if (previous.isNotEmpty) before = before.substring(previous.last.end);
    final next = breaks.firstMatch(after);
    if (next != null) after = after.substring(0, next.start);
    final clause = '$before${m[0]}$after';
    var sb = message.substring(m.start < 160 ? 0 : m.start - 160, m.start);
    var sa = message.substring(m.end, message.length - m.end < 160 ? message.length : m.end + 160);
    final ps = _sentenceBreak.allMatches(sb);
    if (ps.isNotEmpty) sb = sb.substring(ps.last.end);
    final ns = _sentenceBreak.firstMatch(sa);
    if (ns != null) sa = sa.substring(0, ns.start);
    if (meant.any((r) => r.hasMatch('$sb${m[0]}$sa')) || _meantNext.hasMatch(_andNext(message, m.end))) return false;
    final at = before.length, end = before.length + m[0]!.length;
    final near = _accident.allMatches(clause).any((a) {
      final gap = a.end <= at ? clause.substring(a.end, at) : a.start >= end ? clause.substring(end, a.start) : '';
      return _word.allMatches(gap).length <= 5;
    });
    if (!near) return false;
  }
  return count > 0;
}

// "What if I cut myself?" while chopping vegetables, "I worry I'll burn myself": an intrusive fear (harm OCD, health
// anxiety), not self-harm (round 5 review, D-09); never when the sentence says it is wanted, an urge, or again
final _fearOfHarm = _ci(r"\b(what if|worr\w*|scared|afraid|frightened|terrified|fear\w*|panic\w*|(kept|keep|keeps) thinking|thought)( that)?( i| i.?ll| i will| i might|"
    r" i could| i would| i.?d| i was going to| i.?m going to| i was gonna)? (accidentally )?(cut|burn|hurt) (my ?self)\b");
final _wanted = _ci(r"\b(want|wanted|wanting|urges?|tempted|again|tonight|deserve|on purpose|need to|needed to|razors?|"
    r"blades?|can.?t stop thinking)\b");

/// True when every bare "cut / burn myself" in [message] is said as a fear ([_fearOfHarm]) and its sentence never says
/// it is wanted ([_wanted]). At most 30 are read, each in a sentence of at most 320 characters.
bool _onlyFears(String message) {
  var count = 0;
  for (final m in _cutOrBurnMyself.allMatches(message)) {
    if (++count > 30) return false;
    var sb = message.substring(m.start < 160 ? 0 : m.start - 160, m.start);
    var sa = message.substring(m.end, message.length - m.end < 160 ? message.length : m.end + 160);
    final ps = _sentenceBreak.allMatches(sb);
    if (ps.isNotEmpty) sb = sb.substring(ps.last.end);
    final ns = RegExp('[.!?;]').firstMatch(sa);
    if (ns != null) sa = sa.substring(0, ns.start);
    final sentence = '$sb${m[0]}$sa';
    if (!_fearOfHarm.hasMatch(sentence) || _wanted.hasMatch(sentence) || _wantedNext.hasMatch(_andNext(message, m.end))) {
      return false;
    }
  }
  return count > 0;
}

// Fear of not waking up (health anxiety) is not a wish not to wake up: those become a concern, not a crisis.
// "I'm so anxious and I hope I don't wake up" is a wish, not a fear (round 4 review, B-02): the words between may not
// hope, pray, wish, rather or want.
final _fearOfWaking = _ci(r"\b(fear|afraid|scared|worr\w+|what if|anxious|terrif\w+)\b"
    r"((?!\b(hope|hoping|hoped|pray|praying|wish|wishing|rather|want|wanting)\b)[^.!?]){0,60}"
    r"\b(won.?t|not|never|don.?t|didn.?t|wouldn.?t|might not|may not) wake up\b");

final _concern = <String, RegExp>{
  'cannot go on': _ci(r"\bI (can.?t|cannot) (go on|keep going)\b|what.?s the point (of|in) (living|anything|it all|going on)|"
      r"\b(if|whether) (this |my )?life is (even )?worth living|\blife (isn.?t|is not|is no longer) worth living|"
      r"\bnot worth living\b|no point (in )?(living|going on)|\bI (just )?want to disappear(?! (completely |entirely )?from (the internet|social media|online|my phone))|don.?t want to live like this"),
  'hurting myself': _hurtMyself,
};

// "I'm back there", but not "I could see him back there" (security review 2026-11-14, N4)
// "It's too much. I feel like I'm going to pass out." (probe reliv-04): overwhelm and feeling faint pause trauma work
// too; the classifier no longer asks for it since it favours precision (helper C, 2026-11-14)
//
// Round 8 (H7-08, round 7 review B): everyday stress words paused trauma work. These no longer pause, since they say
// nothing about the exercise now: "my shoulder can't take any more tackles" (a thing that can't be taken, not "I can't
// take any more"), "can't take it seriously", "my heart is racing before my driving test", "it's all too much this
// week but I'll get through it", "it's too much pressure", "she can't do this anymore", a thought in quotation marks
// ("I kept thinking, "I can't do this""), and stopping described rather than asked for: "how to stop it", "I can't
// seem to make it stop", "as soon as I stop". "I want to stop", "please make it stop", "I can't take any more", "it's
// too much", "my heart is racing" and "I'm so stressed my hands are shaking" (a sign of distress now, whatever its
// cause) still pause.
const _notAsking = r"(?<!\b(?!(?:want|wanna|need|have|got|like|love|ready|going|you)\b)[a-z’']+ to (make (it|him|her|this|them) )?)"
    r"(?<!\b(when|whenever|once|if|until|till|before|after|soon as|moment|time) (i|we|you|they|he|she) )";
const _toThat = r"(?<!\b(?!(?:want|wanna|need|have|got|like|love|ready|going|you)\b)[a-z’']+ to )";
final _pause = _ci('$_notAsking' r"(?<!\b(when|if|won.?t|wouldn.?t|couldn.?t|didn.?t|doesn.?t|don.?t|never|can.?t|cannot|seem to|bus|full|pit|one|non|a|the|him to|her to|them to|it all to|everything to|it to) )\b(stop|pause)( (it|this|now|please|here|for (now|a (bit|moment|minute|second|while))))*\s*([.!?,;]|$)|"
    r"\b(can we|could we|let.?s|please) (stop|pause)\b|" '$_toThat' r"\bmake (it|him|her|this|them) (stop|pause)\b|"
    r"\b(can we|could we|let.?s|i need|i need to|i want to|please can we) (take |have )?a (break|breather|moment)\b|\bno more\s*(please)?\s*([.!?,]|$)|^\s*(enough|help|no+|please)\s*[.!]*\s*$|"
    r"\bi (want|need) (out|to get out)\b|(?<!\b(she|he|they) )\bcan.?t (continue\s*([.!?,]|$)|do (it|this) any ?more\b)|\bdon.?t want to do this any ?more\b|"
    r"\b(my heart is|my heart.?s|heart.?s) (racing|pounding)\b(?! (a bit |a little )?(before|ahead of)\b)|\bhyperventilat\w*|\bdissociat\w*|\b(nothing|this|it) (feels|is|isn.?t) (not )?real\b|"
    r"\b(it.?s|it is) happening again\b|\b(going to|gonna) (be sick|vomit)\b|(?<!remember(ed)? thinking (that )?i )\bcan.?t breath\b|\bi.?m (there|back) again\b|"
    r"\b(i.?m|i am|im)( \w+){0,2} (panicking|shaking|trembling|freaking out|losing it)\b|\b(having|starting|i think i.?m having) a panic attack\b|"
    r"(?<!remember(ed)? thinking (that )?i )can.?t breathe|\bi.?m back there\b|(?<![\x22“”‘]\s?)\bi can.?t do this(?! (right|properly)\b)|feel(ing)? (unreal|numb|far away)|"
    r"(?<![\x22“”‘]\s?)\b(it.?s|this is|that.?s) (all )?too much\b(?!\s?[\x22“”’])"
    r"(?! (pressure|work|homework|noise|money|time|effort|responsibility|information|food|coffee|sugar|caffeine)\b)"
    r"(?! (this|last|these|that) (week|month|term|year|semester|days?)\b)(?! (lately|recently|at (work|school|uni|home))\b)"
    r"(?![^.!?]{0,60}\bbut (i.?ll|i will|i can|i.?m|i am|we.?ll) (get through|manage|cope|handle|be (ok|okay|fine|alright)|ok|okay|fine|alright|managing|coping)\b)|"
    r"\b(going to|gonna|about to|might|could) (pass out|faint|throw up)\b|"
    r"\b(feel|feeling) (faint|dizzy|sick|like i.?m (going to|gonna) (pass out|faint))|"
    r"\bcan.?t take ((this|it)\b(?! (seriously|personally|lightly|easy|back|home|off|away|anywhere|with me)\b)|"
    r"any ?more\b(?! (?!(of|this|that|it|its|now|please|right|today|tonight|and|but|or|so|as|is|was|i|we|you|us|yes|plus)\b)[a-z]+s\b))|"
    r"\bpanic attack (now|right now|coming)\b|\b(hands?|body|legs?) (is|are|keep|won.?t stop)( \w+)? (shaking|trembling)\b");
const _traumaWork = {'reliving', 'written_exposure'};

/// The text as the phrase rules read it (security review 2026-11-14, SAFE-1): invisible format characters (zero-width
/// spaces and joiners, the word joiner, the byte-order mark, soft hyphens: Unicode category Cf) are removed, curly
/// apostrophes become straight ones, and every run of spaces, no-break spaces and line breaks becomes one space. So
/// "I  want to\ndie", or a word with a zero-width space hidden inside, reads as it was meant. Only the rules read it;
/// what is kept and shown is the person's own text.
String forRules(String text) => text
    .replaceAll(_format, '')
    .replaceAll(_curly, "'")
    .replaceAll(_spaces, ' ');
final _format = RegExp(r'\p{Cf}', unicode: true);
final _curly = RegExp('[\u2018\u2019\u02BC\u2032]');
final _spaces = RegExp(r'\s+'); // in Dart, \s includes the no-break space and the other Unicode spaces

// Everyday senses of crisis words that the rules above leave quiet on purpose (their lookaheads), as whole phrases,
// never a single word: set aside before the classifier's second reading (SafetyResult.setAside, round 5 review D-05).
// A phrase here never silences a rule: it is only read when no rule found a sign.
final _everyday = _ci([
  // waking at a time or for a reason ('not wanting to live' leaves these out); never "at all"
  r"\b(want to |wanna )?wake up (super |that |so |too |very |this |as )?(early|late|on time|in time|before (work|school|"
      r"class|dawn|six|seven|eight|nine|\d+)|at \d[\d:.]*( ?[ap]\.?m\.?)?|at (dawn|sunrise|five|six|seven|eight|nine)|"
      r"for (work|school|class|uni|college|my shift|the (gym|flight|train|meeting|interview))|until (noon|lunch|midday|\d+))\b|",
  // goodbyes at an event ('goodbyes and arrangements' leaves these out) and the events themselves
  r"\b(saying|said|say|says) goodbye to (people|everyone|everybody|friends|my family|colleagues|the team) (at|after|"
      r"before) (the|my|our|a|his|her) (party|meeting|airport|station|wedding|funeral|leaving (party|do|drinks)|end|office|"
      r"school)\b|\b(leaving|farewell|going-away|going away|retirement) (party|do|drinks|dinner|card|lunch)\b|",
  // rope and cord for an ordinary job ('means and plans' leaves these out)
  r"\b(rope|ropes|cord|twine|bungee cords?)( \w+){0,2} for (the |a |my |our )?(tent|climbing|camping|sailing|boat|swing|"
      r"move|removal|washing line|clothes ?line|garden|allotment|van|trailer|roof rack|dog|horse|gym|tug of war)\b|",
  // hanging things up, hanging out
  r"\bhang(ing|s)? (up )?(the |some |my |a |our |those |these |new )?(pictures?|photos?|paintings?|curtains?|blinds|"
      r"washing|laundry|clothes|shelf|shelves|mirror|lights|fairy lights|decorations|bunting|wallpaper|art|prints?|posters?|"
      r"frames?|coat|jacket)\b|\bhang(ing)? out (with|at|in|together)\b|",
  // taking my life back or in hand ('suicide' leaves these out)
  r"\btake my (own )?life (back|into my own hands|in (a|my|both|new) (\w+ )?(direction|hands?)|seriously|more seriously|"
      r"for granted|one day at a time|step by step)\b|",
  // ending a relationship or an event ('suicide' leaves these out)
  r"\bend(ing)? (it|things) (with (him|her|them|my (boy|girl)friend|my partner|my (husband|wife|fianc[eé]e?|ex))\b(?![^.!?;]{0,60}"
      r"\b(myself|my life|pills?|tablets?|gun|rope|knife|blade|overdose|bridge|jump))|on a (high|good|positive) note\b)",
].join());

// A mood that sets it off or a nightly habit (owner's D-05 measurement, 2026-11-15: "I cut myself with a can opener
// when I'm sad", "I burn myself with the kettle when things get bad", "Most nights I cut myself in the gym changing
// room" read as accidents to the rules, and only the classifier caught them): a message with one of these has nothing
// plainly safe in it, so nothing is set aside and the classifier's worry stands as it is. The rules stay quiet on them
// as before ("I burn myself on the oven when I'm stressed and rushing" can be an accident).
final _notPlainly = _ci(r"\bwhen(ever)? (things|it|life|stuff|everything) (get|gets|got|is|are|was|were|feels?|felt)"
    r"( so| really| too| very)? (bad|worse|hard|much|dark|heavy|overwhelming|unbearable|a lot)\b|"
    r"\bwhen(ever)? (i.?m|i am|i was|i feel|i felt|i get|i got|i.?ve been)( so| really| too| very| feeling)? (sad|upset|"
    r"angry|low|down|stressed|anxious|overwhelmed|lonely|empty|numb|depressed|bad|awful|terrible|panicky|triggered|"
    r"hopeless|worthless|hurt|rejected|ashamed|guilty|disgusted|furious|desperate|alone|drunk|high)\b|"
    r"\b(most|every|some|many|all) (nights?|evenings?)\b|\bnight after night\b|\bagain and again\b|\bwhenever\b|"
    r"\b(to|so i can|so i) (feel|cope|calm|numb|forget|punish|release|distract)\b|\bhabit\b");

// Words that may still carry a risk once the plainly safe phrases are set aside: if any is left, the classifier's
// worry stands. Broad on purpose (only short, plainly safe sentences should pass): an ending, a means, a place, a
// farewell, being gone or a burden, a time, a wish, "never", "ever again", "anymore".
final _riskLeft = _ci(r"\b(die|died|dies|dying|dead|death|deadly|kill\w*|suicid\w*|end (it|things|everything|my life|this|"
    r"all)|my life|live|living|alive|exist\w*|wake|waking|sleep (forever|for ever)|hurt\w*|harm\w*|cut\w*|burn\w*|"
    r"bleed\w*|bled|blood|scar\w*|pills?|tablets?|meds|medication|overdos\w*|rope|noose|belt|hang\w*|hung|jump\w*|"
    r"bridge|cliff|ledge|roof|edge|train|tracks|drown\w*|gun|knife|knives|blade|razor|poison|bleach|goodbyes?|farewell|"
    r"notes?|letters?|will|disappear\w*|vanish\w*|gone|leave|leaving|nobody|no one|no-one|anyone|better off|burden|"
    r"point|pointless|reason|hopeless|worthless|give up|giving up|go on|keep going|cope|done|over|tonight|forever|"
    r"for ever|ever|for good|never|come back|miss|sorry|plan\w*|ready|escape|here|anymore|any more|numb|empty|alone|"
    r"lonely|tired of|want|wanna|wish|rather|deserve\w*|hate|again|still|myself|me|purpose|deliberate\w*|intentional\w*|meant|"
    r"pain|blood|deep\w*|kept|keep|keeps|help|helps|only|stop|relief|release|feel|every|habit|blades|punish\w*|stitch\w*|"
    // round 7 review, H7-04: a means or a time in the rest ("then I'm taking the whole bottle", "strong enough to hold my
    // weight", "the tree in the woods is perfect")
    r"take|taking|took|swallow\w*|bottle|whole|tree|woods?|forest|weight|hold|vodka|alcohol|drink\w*|tomorrow|tonight|"
    r"now|finally|perfect|strong|enough|ready|sorted|rope|cord|"
    // audit 216, H7-04: a place ("then I'm off to the railway line"). Round 10 review B (R10B-02): not "at all", "line"
    // or "platform", which sent plain denials ("I'm not suicidal at all") back to the classifier; the second-part
    // check below already reads "...on Saturday. Or at all." and "...then I'm off to the railway line"
    r"railways?)\b");

/// Audit 216 (H7-04 and S3), widened in round 10 review B (R10B-01): something more after the plainly safe words, in
/// what is left once they are set aside. Plainly safe only when that rest is one run of words with at most a final
/// full stop, exclamation or question mark. Anything else starts a second part, so the classifier reads the message:
/// - a line break (noted in [SafetyCheck.check] before the spaces are made one);
/// - any other mark: a comma, colon, semicolon, bracket, dash, quote mark, emoji, or another script's full stop
///   ("I'm not suicidal, actually I am.", "Not suicidal (I am)", "Hanging up the washing — off to the river after");
/// - a sentence end with more words after it ("I'm not suicidal. Actually, I am.");
/// - a letter of another script;
/// - a joining word ("and", "so", "then", "but", "or", "because", "actually", "though": "Hanging up the washing and
///   after that the river", "I'm not suicidal so yeah I am").
/// Marks inside a word or a number stay ("I'm", "follow-up", "7.30", "7:30"). A second part in another language
/// written in Latin letters ("pero sí lo soy") is not seen: a known limit (round 10 review B).
bool _hasMorePart(String rest) {
  final r = rest.replaceAll(_inWordMark, '').replaceAll(_inNumberMark, '').trim().replaceFirst(_finalStop, '');
  return _otherMark.hasMatch(r) || _otherScript.hasMatch(r) || _joining.hasMatch(r);
}

final _lineBreak = RegExp('[\r\n\u000B\u000C\u0085\u2028\u2029]');
final _inWordMark = RegExp(r"(?<=\p{L})['’\-‐](?=\p{L})", unicode: true);
final _inNumberMark = RegExp(r'(?<=\p{N})[.:,](?=\p{N})', unicode: true);
final _finalStop = RegExp(r'[.!?]+$');
final _otherMark = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final _otherScript = RegExp(r'(?=\p{L})\P{Script=Latin}', unicode: true);
final _joining = RegExp(r"\b(and|so|then|but|or|because|cos|coz|cause|actually|though|although|except|unless|plus|"
    r"anyway)\b", caseSensitive: false);

/// Notes where [rule] matches in [message], widened to whole words ("suicid" is the rule, "suicide" the word): at
/// most 30 places, and any more stay in, so the classifier still reads them.
void _setAside(List<(int, int)> aside, RegExp rule, String message) {
  var count = 0;
  for (final m in rule.allMatches(message)) {
    if (++count > 30) return;
    var start = m.start, end = m.end;
    while (start > 0 && _letter.hasMatch(message[start - 1])) {
      start--;
    }
    while (end < message.length && _letter.hasMatch(message[end])) {
      end++;
    }
    aside.add((start, end));
  }
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// [message] with the places in [aside] taken out (each becomes a space).
String _without(String message, List<(int, int)> aside) {
  aside.sort((a, b) => a.$1.compareTo(b.$1));
  final out = StringBuffer();
  var at = 0;
  for (final (start, end) in aside) {
    if (end <= at) continue;
    if (start > at) out.write(message.substring(at, start));
    out.write(' ');
    at = end;
  }
  out.write(message.substring(at));
  return out.toString();
}

/// Spelling games the rules would otherwise miss (round 6 review, F6-14): a digit or symbol standing for a letter between
/// two letters ("su1cidal", "k1ll", "d1e") and a word spelt out in single letters ("s u i c i d e"). Null when there are
/// none. Linear in the length.
String? _folded(String message) {
  var out = message.replaceAllMapped(_leet, (m) => _leetLetters[m[0]!] ?? m[0]!);
  out = out.replaceAllMapped(_spelt, (m) => m[0]!.replaceAll(' ', ''));
  return out == message ? null : out;
}

final _leet = RegExp(r'(?<=\p{L})[013457@$](?=\p{L})', unicode: true);
const _leetLetters = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', r'$': 's'};
final _spelt = RegExp(r'\b(?:\p{L} ){3,}\p{L}\b', unicode: true);

class SafetyCheck {
  const SafetyCheck();

  SafetyResult check(String text, {required String sessionKind}) {
    final message = forRules(text);
    // forRules makes every run of spaces one space, so a line break is noted first (round 10 review B, R10B-01)
    final breaks = text.trim().contains(_lineBreak);
    final result = _check(message, sessionKind, breaks);
    if (result.level == SafetyLevel.crisis) return result;
    // spelling games (round 6 review, F6-14): read again folded; only a crisis there counts, so folding never adds a
    // false alarm of any other kind
    final folded = _folded(message);
    if (folded == null) return result;
    final again = _check(folded, sessionKind, breaks);
    return again.level == SafetyLevel.crisis ? again : result;
  }

  SafetyResult _check(String message, String sessionKind, bool breaks) {
    // A fear of not waking up is a concern, but it must not hide a crisis rule further down the list ("I'm scared I
    // won't wake up. I took 30 pills."): it is returned only when no crisis rule matches (OW-A06-1 follow-up).
    var fearOfNotWaking = false;
    final aside = <(int, int)>[]; // phrases read as plainly safe (SafetyResult.setAside)
    for (final e in _crisis.entries) {
      if (!e.value.hasMatch(message)) continue;
      if (_deniable.contains(e.key) && _spokenAway(e.value, message)) {
        _setAside(aside, e.value, message);
        continue;
      }
      if (e.key == 'not wanting to live' && _fearOfWaking.hasMatch(message) &&
          e.value.allMatches(message).every((m) => RegExp(r'wake up', caseSensitive: false).hasMatch(m[0]!) && !RegExp(r'want', caseSensitive: false).hasMatch(m[0]!))) {
        fearOfNotWaking = true;
        continue;
      }
      return SafetyResult(SafetyLevel.crisis, e.key);
    }
    if (_cutOrBurnMyself.hasMatch(message)) {
      if (!_onlyAccidents(_cutOrBurnMyself, message, _clauseBreak, [_meant, _meantCrisis, _accidentAsSubject]) &&
          !_onlyFears(message)) {
        return const SafetyResult(SafetyLevel.crisis, 'self-harm');
      }
      _setAside(aside, _cutOrBurnMyself, message); // an accident or a fear
    }
    if (_namedViolence.hasMatch(message)) return const SafetyResult(SafetyLevel.crisis, 'violence at home');
    if (fearOfNotWaking) return const SafetyResult(SafetyLevel.concern, 'fear of not waking up');
    if (_traumaWork.contains(sessionKind) && _pause.hasMatch(message)) {
      return const SafetyResult(SafetyLevel.pause, 'distress during trauma work');
    }
    for (final e in _concern.entries) {
      if (!e.value.hasMatch(message)) continue;
      if (e.key == 'hurting myself' &&
          (_onlyAccidents(_hurtMyself, message, _sentenceBreak, [_meant]) || _spokenAway(_hurtMyself, message))) {
        _setAside(aside, _hurtMyself, message);
        continue; // an accident, or a plain denial ("no thoughts of hurting myself, just tired"): no support line
      }
      return SafetyResult(SafetyLevel.concern, e.key);
    }
    _setAside(aside, _everyday, message);
    final rest = aside.isEmpty ? '' : _without(message, aside);
    // round 7 review, H7-04: only a short message is plainly safe; a longer rest may say anything, so it is read.
    // Audit 216 (H7-04 and S3): and only one that is a single sentence of a single clause, so nothing follows the
    // plainly safe words: "Hanging up the washing, then I'm off to the railway line", "I don't want to wake up early
    // on Saturday. Or at all." and a denial taken back ("I'm not suicidal. Actually, I am.") are read by the classifier
    if (aside.isEmpty || _notPlainly.hasMatch(message) || _riskLeft.hasMatch(rest) || breaks || _hasMorePart(rest) ||
        _word.allMatches(rest).length > 8) {
      return const SafetyResult(SafetyLevel.none);
    }
    return const SafetyResult.safeReading();
  }
}

// The model's own words (security review 2026-11-14, AI-4). Its training is not the only thing between a reply and a
// way or a means to die: each sentence of a reply is read before the person sees or hears it, and one that gives a
// method or a means is replaced (core/check_in_guard.dart, ReplyScreen). These are the two rule groups above, 'method
// seeking' and 'overdose', as they read in the therapist's mouth. The person's rules catch someone asking or telling;
// a therapist reflecting that back with care must still pass ("It sounds like you've thought about an overdose, and
// I'm glad you told me"; "I'm so sorry about your brother's death from an overdose"; "It took courage to tell me about
// the pills"). So 'method seeking' is kept word for word, except that a death someone had ("his death from an
// overdose") is a reflection, not a method. 'overdose' keeps its two means rules, narrowed to the means (how many
// tablets it would take; tablets taken with drink), counts the word itself only beside a means detail (an amount, a
// dose, a drug, how deadly), and drops the two parts that describe what the person did (took; saving up tablets),
// which a caring reply repeats. test/reply_screen_test.dart holds the replies that must pass and those that must not.
const _drugs = r'pills|tablets|xanax|valium|diazepam|lorazepam|codeine|painkillers|paracetamol|acetaminophen|tylenol|'
    r'ibuprofen|aspirin|antidepressants|insulin';
const _detail = r'\d+ ?(mg|milligrams?|grams?|ml)|doses?|amounts?|lethal|fatal|deadly';
const _means = r'(carbon monoxide|car exhaust|hanging|an overdose)';

final _meansInReplies = <String, RegExp>{
  'method seeking': _ci([
    r'\b(highest|tallest) (bridge|building|cliff|car park|tower)s?\b|',
    r'how long (does|would|will) it take to die|',
    r'\b(die|dying) (from|of|by) ', _means, '|',
    r"(?<!\b(your|his|her|their|my|our)( \w+)? |['’]s( \w+)? )\bdeath (from|of|by) ", _means, '|',
    r'carbon monoxide.{0,30}\b(die|dying|death|kill)|',
    r'\bcut(ting)? (along|across|down|up) (the|my|your) (arm|wrist)s?|',
    r'\b(along|across) (the|my|your) (arm|wrist)s?.{0,40}(worse|better|deeper|faster|more dangerous)|',
    r'\b(lethal|fatal) dose\b(?! of (caffeine|coffee|espresso|sugar|chocolate|sarcasm|reality|cuteness|nostalgia|work|meetings|tv|telly|netflix)\b)|\bpainless (way|method)s? to (die|go|kill)|',
    r'\b(quickest|easiest|fastest|surest) way to (die|kill (myself|yourself))',
  ].join()),
  'overdose': _ci([
    r'overdos\w*.{0,60}\b(', _detail, '|', _drugs, r'|liver|kidneys?|organs?)\b|',
    r'\b(', _detail, '|', _drugs, r')\b.{0,60}overdos|',
    r'how many .{0,40}\b(', _drugs, r')\b.{0,30}\b((would|will|does|do) it take|to (die|kill|end)|',
    r'(is|are|would be) (enough|fatal|lethal|deadly))|',
    r'\b(\d+|a few|several|a handful of|enough) (\w+ ){0,2}(', _drugs, r')\b.{0,40}',
    r'\b(enough to|fatal|lethal|deadly|kills?|die|dying|death|overdose)\b|',
    r'(pills|tablets).{0,30}(take|taking).{0,12}with .{0,15}(whisky|whiskey|alcohol|wine|beer|vodka|drink)',
  ].join()),
};

/// The rule group ('method seeking' or 'overdose') a sentence of the model's reply falls in, or null when it is safe
/// to show. Only ever the group's name leaves here, never the sentence.
String? meansInReply(String sentence) {
  final text = forRules(sentence);
  for (final e in _meansInReplies.entries) {
    if (e.value.hasMatch(text)) return e.key;
  }
  return null;
}
