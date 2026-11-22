// The therapist never reads the check-in's numbers back (owner, 2026-11-06: no mood numbers in conversation; the
// check-in is used in words: prompts/writer_rulebook.md, pipeline/formats.py check_in_text). The trained models still
// do: on 2026-11-13 E2B's phone files read the mood back in 18.5 percent (Q5_K_M) and 28.2 percent (Q4_K_M) of first
// replies to held-out people's openings (tests/check_in_readback.py), four to five times the training data's 5.1
// percent. Until the training data is fixed (version 2), the app guards the first reply after a check-in: it comes a
// sentence at a time, each checked once complete. A sentence that reads a number back is left out; when it would be
// the first thing shown, the reply starts again instead (nothing has been shown yet), twice at most. The person never
// sees or hears the number. The same sentence check keeps every reply from naming a mode (namesMode, below), and
// screens every sentence for a way or a means to die and for quotes of the session's mode line (ReplyScreen, below).
import 'formats.dart';
import 'model.dart';
import 'safety.dart';

const _words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
// a number followed by these is something else ("a 10-minute walk", "four days")
const _notANumberRead = r'(?!-|\s*(minutes?|days?|times?|weeks?|hours?|months?|of the|things?|steps?|people)\b)';

/// The opening used if every try read a number back (about 1 in 100 at the measured rate, before leaving sentences
/// out): plain, in the training data's own words.
const fallbackOpening = "It's good to see you. How are you feeling today?";

/// True when [text] reads a number from [c] back: the mood (0 to 10, as a digit or a word) or the practice's distress
/// at the start or the end (0 to 100). The mood pattern is the one tests/check_in_readback.py counts with.
bool readsBack(String text, CheckIn c) {
  final m = c.mood;
  if (m != null && m >= 0 && m <= 10) {
    final v = '($m|${_words[m]})';
    if (RegExp('\\b$v\\s*(out of|/)\\s*(10|ten)\\b|\\b(a|an|at|your|was|is|of)\\s+$v\\b$_notANumberRead',
        caseSensitive: false).hasMatch(text)) {
      return true;
    }
  }
  for (final d in [c.start, c.end]) {
    if (d != null && RegExp('\\b$d\\s*(%|percent|out of (100|a hundred))|\\b(from|to|at|of|was|a|an)\\s+$d\\b'
        '$_notANumberRead', caseSensitive: false).hasMatch(text)) {
      return true;
    }
  }
  return false;
}

/// True when [text] names one of the app's modes ("full mode", "deep work mode"): deep work mode stays tucked away in
/// Settings behind its key (owner, 2026-11-13; TASKLIST B12), so no therapist reply may name a mode (F8). On 2026-11-13
/// one of 2,968 session replies of the trained E4B did ("Since we're meeting in full mode today"): its prompt's mode
/// line begins "Full.".
bool namesMode(String text) => _modeName.hasMatch(text);
final _modeName = RegExp(r'\b(full|normal|deep[- ]work|everyday)[- ]mode\b', caseSensitive: false);

bool _bad(String sentence, CheckIn checkIn) => readsBack(sentence, checkIn) || namesMode(sentence);

// "Mode:" as a label (the prompt's own line starts with it), but not "survival mode: always on alert".
final _modeLabel = RegExp(r"(?<![A-Za-z][\s\-]?)\bmode\b\W{0,3}:|"
    r"\bmode\W{0,3}:\W{0,3}(normal|full|deep[- ]work|everyday)\b", caseSensitive: false);
final _word = RegExp(r'[a-z0-9]+');
String _wordsOf(String s) => [for (final m in _word.allMatches(s.toLowerCase())) m[0]!].join(' ');

/// True when [sentence] quotes the session's mode line (security review 2026-11-14, AI-4: asked to repeat its
/// instructions, the model said "Mode: Normal. ... Do not lead spoken reliving", which tells the person another mode
/// exists). A quote is the "Mode:" label, any seven words in a row from one part of [modeLine], a whole part of four
/// words or more ("if asked, offer the written approach"), or an instruction without its "do not" ("lead spoken
/// reliving"). Shorter pieces, such as "the written approach" or "Written Exposure Therapy", are ordinary words the
/// therapist is told to use.
bool quotesModeLine(String sentence, String modeLine) {
  if (_modeLabel.hasMatch(sentence)) return true;
  final said = ' ${_wordsOf(sentence)} ';
  bool has(List<String> words) => words.isNotEmpty && said.contains(' ${words.join(' ')} ');
  for (final part in modeLine.split(RegExp(r'[.;:()]'))) {
    final w = _wordsOf(part).split(' ').where((x) => x.isNotEmpty).toList();
    if (w.length >= 4 && has(w)) return true;
    for (var i = 0; i + 7 <= w.length; i++) {
      if (has(w.sublist(i, i + 7))) return true;
    }
    final rest = w.length > 2 && w[0] == 'do' && w[1] == 'not' ? w.sublist(2) : w.isNotEmpty && w[0] == 'never'
        ? w.sublist(1) : const <String>[];
    if (rest.length >= 3 && has(rest)) return true;
  }
  return false;
}

/// What replaces a sentence of a reply that gives a way or a means to die (core/safety.dart, meansInReply). It names
/// Support without saying where, because the button is at the top of the chat and at the foot of the call.
const meansFallback = "I'm not able to go into that, but I'm here with you, and Support has people you can talk to "
    'right now.';

/// What replaces a sentence that quotes how the session was set up (quotesModeLine).
const setupFallback = "I can't share how I'm set up, but I'm here with you.";

/// What replaces a sentence of a reply that gives a phone number (phoneInReply). Like [meansFallback] it names Support
/// without saying where the button is.
const phoneFallback = 'Support has the right numbers for where you are, at any time.';

/// The rule group of a sentence that gives a phone number (phoneInReply), as recorded.
const phoneGroup = 'phone number';

/// Round 5 review, D-12: true when [sentence] (one sentence of the model's reply) gives a phone number or a hotline's
/// digits. The app's Support list is chosen for the person's country and dated; a number the model writes is neither,
/// and it would be shown and spoken as plain, authoritative text ("Please call 988" to someone in France). Caught:
/// a run of 7 digits or more written as phone numbers are ("+44 20 7946 0958", "1-800-273-8255", "(555) 123-4567",
/// "0800 1111"); a run of 3 digits or more in a sentence about calling or texting ("call 988", "text HOME to 741741",
/// "ring the Samaritans on 116 123"); and the best-known crisis codes on their own ("988 is there for you"). Left
/// alone: numbers in everyday prose (times such as 10:30, 7.30 or 7pm, years and dates, "6 out of 10", "6/10", "24/7",
/// "100mg", "£250", "a 0 to 100 scale", "200 words", counting "5-4-3-2-1"). One pass over the sentence: linear in its
/// length, whatever it holds.
bool phoneInReply(String sentence) {
  final s = sentence, n = s.length;
  bool? calling; // whether the sentence is about calling or texting: looked at once, only when it matters
  for (var i = 0; i < n;) {
    final c = s.codeUnitAt(i);
    if (!_digit(c) && !((c == 0x2B || c == 0x28) && i + 1 < n && _digit(s.codeUnitAt(i + 1)))) {
      i++;
      continue;
    }
    // one run: groups of digits joined by one or two separators ("+44 (0)20 7946-0958"); [i] moves past its last digit
    final groups = <int>[], joined = StringBuffer();
    final start = _digit(c) ? i : i + 1;
    var j = i, group = 0, gap = 0, end = start, dots = false, others = false;
    for (; j < n; j++) {
      final d = s.codeUnitAt(j);
      if (_digit(d)) {
        group++;
        joined.writeCharCode(d);
        gap = 0;
        end = j + 1;
      } else if (_separator(d) && gap < 2) {
        if (group > 0) groups.add(group);
        group = 0;
        gap++;
        if (d == 0x2E) {
          dots = true;
        } else if (d != 0x20 && d != 0xA0) {
          others = true;
        }
      } else {
        break;
      }
    }
    if (group > 0) groups.add(group);
    i = end;
    if (!_standsAlone(s, start, end)) continue;
    final digits = joined.toString();
    if (digits.length >= 7 && _phoneShaped(groups, digits, dots: dots, others: others)) return true;
    if (digits.length < 3 || _clock(groups, dots) || _year(groups, digits)) continue;
    if (_crisisCodes.contains(digits)) return true;
    // beside a word about calling, a short code too: one group ("999"), or groups of two or more digits after an
    // optional country or trunk digit ("116 123", "13 11 14", "1-800"), never "24-7" or a time
    final short = groups.length == 1 || (digits.length >= 4 && groups.skip(1).every((g) => g >= 2));
    if (short && (calling ??= _callWords.hasMatch(s))) return true;
  }
  return false;
}

bool _digit(int c) => c >= 0x30 && c <= 0x39;

/// A letter of any script (not punctuation, a symbol or a space).
bool _letter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 && c <= 0x1FFF && c != 0xD7 && c != 0xF7) || (c >= 0x2C00 && c < 0xD800 && (c < 0x3000 || c > 0x303F));

// space, no-break space, "-", ".", "(", ")", "+", and the en dash
bool _separator(int c) =>
    c == 0x20 || c == 0xA0 || c == 0x2D || c == 0x2E || c == 0x28 || c == 0x29 || c == 0x2B || c == 0x2013;

/// False when the digits from [start] to [end] belong to something else: a word or a unit ("GAD7", "100mg", "5pm",
/// "3rd", "200 words"), a time ("10:30"), a fraction or a date with slashes ("6/10", "24/7"), money ("£250", "$40"),
/// a percentage, or a number written with commas ("12,000").
bool _standsAlone(String s, int start, int end) {
  if (start > 0) {
    final b = s.codeUnitAt(start - 1);
    if (_letter(b) || b == 0x3A || b == 0x2F || b == 0x23 || b == 0x24 || b == 0xA3 || b == 0xA5 || b == 0x20AC) {
      return false;
    }
    if (b == 0x2C && start > 1 && _digit(s.codeUnitAt(start - 2))) return false;
  }
  if (end < s.length) {
    final a = s.codeUnitAt(end);
    if (_letter(a) || a == 0x3A || a == 0x2F || a == 0x25) return false;
    if (a == 0x2C && end + 1 < s.length && _digit(s.codeUnitAt(end + 1))) return false;
    // "100 percent", "200 words": the next word is a unit or a thing counted (at most 12 letters are read)
    if (a == 0x20) {
      var k = end + 1;
      final word = StringBuffer();
      while (k < s.length && k <= end + 12 && _letter(s.codeUnitAt(k))) {
        word.writeCharCode(s.codeUnitAt(k++));
      }
      if (_counted.contains(word.toString().toLowerCase())) return false;
    }
  }
  return true;
}

const _counted = {'percent', 'per', 'mg', 'ml', 'g', 'kg', 'lb', 'lbs', 'km', 'miles', 'metres', 'meters', 'steps',
  'seconds', 'minutes', 'mins', 'hours', 'hrs', 'days', 'weeks', 'months', 'years', 'times', 'people', 'words',
  'pages', 'calories', 'points', 'pounds', 'euros', 'dollars', 'quid', 'pence', 'cents', 'am', 'pm'};

/// "7.30" or "10.30": a time written with a dot.
bool _clock(List<int> groups, bool dots) => dots && groups.length == 2 && groups[0] <= 2 && groups[1] == 2;

/// "2027", alone.
bool _year(List<int> groups, String digits) => groups.length == 1 && digits.length == 4 &&
    (digits.startsWith('19') || digits.startsWith('20'));

/// A run of 7 digits or more written as a phone number is, rather than counting ("1 2 3 4 5 6 7"), a date or a range
/// of years ("2026-11-14", "14.11.2026", "2019-2020"), or a large number in groups of three ("1 000 000").
bool _phoneShaped(List<int> groups, String digits, {required bool dots, required bool others}) {
  if (groups.where((g) => g == 1).length > 1) return false;
  bool yearAt(int from) => digits.startsWith('19', from) || digits.startsWith('20', from);
  final key = groups.join(',');
  if ((key == '4,2,2' && yearAt(0)) || (key == '4,4' && yearAt(0) && yearAt(4)) ||
      ((key == '2,2,4' || key == '1,2,4' || key == '2,1,4' || key == '1,1,4') && yearAt(digits.length - 4))) {
    return false;
  }
  final thousands = groups.length >= 3 && groups.first <= 3 && groups.skip(1).every((g) => g == 3);
  return !(thousands && !others); // groups of three after spaces or dots only: 1 000 000, 2.500.000
}

final _callWords = RegExp(r'\b(call|calls|calling|dial|dialling|dialing|ring|ringing|phone|text|texting|txt|whatsapp|'
    r'hotline|helpline|lifeline|crisis line|samaritans|shout|emergency)\b', caseSensitive: false);

/// Crisis and emergency numbers a model is likely to have read, caught even with no word about calling beside them.
const _crisisCodes = {'988', '911', '999', '112', '116123', '116111', '741741', '85258', '131114'};

/// The rule group of a sentence that gives a web address or an e-mail address (linkInReply), as recorded. It is
/// treated as a phone number is: replaced by [phoneFallback], never a means.
const linkGroup = 'link';

/// Round 6 review, F6-09: true when [sentence] gives a web address or an e-mail address ("visit www.example.org",
/// "samaritans.org", "jo@samaritans.org", a forum's address). Like a phone number the model writes (phoneInReply), it is
/// neither chosen for the person's country nor checked, and the Support list has the right places. Caught: an address
/// with "://" or starting "www.", an e-mail address, and a name with dots whose last part is a common ending written in
/// small letters (".org", ".co.uk", ".com"). Left alone: "e.g.", "U.S.", "3.5", "a.m.", "Ph.D.", a missing space after a
/// full stop ("a lot.It"). One pass over the sentence, a word at a time: linear in its length.
bool linkInReply(String sentence) {
  final s = sentence, n = s.length;
  for (var i = 0; i < n;) {
    while (i < n && _blank(s.codeUnitAt(i))) {
      i++;
    }
    final start = i;
    while (i < n && !_blank(s.codeUnitAt(i))) {
      i++;
    }
    if (i > start && _linkWord(s.substring(start, i))) return true;
  }
  return false;
}

bool _blank(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0;

/// One word of a sentence (no spaces in it): an address?
bool _linkWord(String word) {
  if (word.contains('://')) return true;
  var w = word;
  // the brackets, quotes and punctuation around a word are not part of an address
  const around = '()[]<>{}"\'“”‘’.,;:!?…';
  var a = 0, b = w.length;
  while (a < b && around.contains(w[a])) {
    a++;
  }
  while (b > a && around.contains(w[b - 1])) {
    b--;
  }
  w = w.substring(a, b);
  if (w.length < 4) return false;
  if (w.toLowerCase().startsWith('www.')) return true;
  final at = w.indexOf('@');
  if (at > 0) return _host(w.substring(at + 1));
  return _host(w.split('/').first);
}

/// A host name: two parts or more, each of letters, digits and hyphens, with a letter somewhere, the first at least
/// two characters long, ending in a common top-level part written in small letters.
bool _host(String h) {
  final parts = h.split('.');
  if (parts.length < 2 || parts.first.length < 2 || !_endings.contains(parts.last)) return false;
  for (final p in parts) {
    if (p.isEmpty || p.length > 63 || !_hostPart.hasMatch(p)) return false;
  }
  return _aLetter.hasMatch(parts.first);
}

final _hostPart = RegExp(r'^[A-Za-z0-9-]+$'), _aLetter = RegExp('[A-Za-z]');

// common endings of web addresses; endings that are also English words ("it", "is", "me", "no", "us", "to", "help",
// "care", "app") are left out, so a missing space after a full stop is never read as an address
const _endings = {'com', 'org', 'net', 'gov', 'edu', 'info', 'uk', 'ie', 'au', 'nz', 'ca', 'fr', 'de', 'eu', 'es', 'nl',
  'ch', 'se', 'dk', 'fi', 'pt', 'pl', 'za', 'sg', 'hk', 'jp', 'br', 'mx', 'io', 'co'};

/// Screens one reply of the model a sentence at a time, before the person sees or hears it (security review
/// 2026-11-14, AI-4). A sentence that gives a way or a means to die ('method seeking', 'overdose') or quotes the
/// session's mode line ('mode line') is replaced by a fallback, each fallback at most once a reply, and the rule group
/// is reported once a reply ([onBlocked]: the session records it as a safety event). Every other sentence passes as it
/// is. One screen serves one reply.
class ReplyScreen {
  ReplyScreen({this.modeLine = '', this.onBlocked});
  final String modeLine;
  final void Function(String group)? onBlocked;
  final _reported = <String>{}, _shown = <String>{};

  /// The rule group [sentence] falls in, or null when it may be shown. A web or e-mail address is screened as a phone
  /// number is (round 6 review, F6-09).
  String? groupOf(String sentence) => meansInReply(sentence) ??
      (quotesModeLine(sentence, modeLine) ? 'mode line' : phoneInReply(sentence) ? phoneGroup
          : linkInReply(sentence) ? linkGroup : null);

  /// What to show for [sentence]: itself; or, when it falls in a group, its fallback the first time that fallback is
  /// needed in this reply ('' after that), keeping the sentence's trailing spaces.
  String pass(String sentence) => _pass(withoutDashes(sentence));

  String _pass(String sentence) {
    final group = groupOf(sentence);
    if (group == null) return sentence;
    if (_reported.add(group)) onBlocked?.call(group);
    final fallback = group == 'mode line' ? setupFallback
        : group == phoneGroup || group == linkGroup ? phoneFallback : meansFallback;
    if (!_shown.add(fallback)) return '';
    return fallback + sentence.substring(sentence.trimRight().length);
  }
}

/// What takes the place of a sentence of the session note or the story that falls in a rule group (screenWritten).
/// They are notes about the person, not Solace speaking, so they say plainly what was left out.
const writtenMeansLine = '(A line about ways of harming was left out, for safety.)';
const writtenNumberLine = '(A phone number or address was left out. Support has the right ones for where you are.)';
const writtenSetupLine = '(A line about how Solace is set up was left out.)';

/// Round 6 review, F6-09: the session note and the story the model writes at End, screened as replies are
/// ([ReplyScreen.groupOf]) before they are shown or kept: line by line and sentence by sentence, each sentence that
/// gives a way or a means to harm, a phone number, a web or e-mail address, or quotes the mode line is replaced by a
/// short bracketed line (each of those at most once, later ones left out), so a heading or the rest of the line stays.
/// [onBlocked] hears each rule group once. Linear in the length of [text] (the model writes at most a few hundred
/// tokens of each); never throws.
String screenWritten(String text, {String modeLine = '', void Function(String group)? onBlocked}) {
  if (text.trim().isEmpty) return text;
  final screen = ReplyScreen(modeLine: modeLine);
  final reported = <String>{}, shown = <String>{};
  String one(String sentence) {
    final group = screen.groupOf(sentence);
    if (group == null) return sentence;
    if (reported.add(group)) onBlocked?.call(group);
    final line = group == 'mode line' ? writtenSetupLine
        : group == phoneGroup || group == linkGroup ? writtenNumberLine : writtenMeansLine;
    final after = sentence.substring(sentence.trimRight().length);
    return shown.add(line) ? '$line$after' : after;
  }

  final out = <String>[];
  for (final line in text.split('\n')) {
    final kept = StringBuffer();
    var from = 0;
    for (final end in _sentenceEnd.allMatches(line)) {
      kept.write(one(line.substring(from, end.end)));
      from = end.end;
    }
    if (from < line.length) kept.write(line.substring(from).trim().isEmpty ? line.substring(from) : one(line.substring(from)));
    out.add(kept.toString());
  }
  return out.join('\n');
}

/// Whether [c] carries any number the therapist could read back.
bool hasNumbers(CheckIn? c) => c != null && !c.skipped && (c.mood != null || c.start != null || c.end != null);

// One complete sentence at the start of [text] with the spaces after it, or null while the first is unfinished.
final _sentenceEnd = RegExp(r'''[.!?…]+["”’)\]]*\s+''');

/// The first reply after a check-in with numbers, a checked sentence at a time (see the top of this file). Every
/// sentence also passes [screen] first (ReplyScreen): what it replaces counts as shown, so it never starts the reply
/// again.
Stream<String> guardedReply(ModelRuntime model, List<Map<String, String>> messages, CheckIn checkIn,
    {int tries = 3, ReplyScreen? screen}) async* {
  final s = screen ?? ReplyScreen();
  for (var t = 1; t <= tries; t++) {
    final last = t == tries;
    var pending = '';
    var shown = false;
    var again = false;
    await for (final piece in model.generate(messages, maxTokens: maxReplyTokens)) {
      pending += piece;
      for (var end = _sentenceEnd.firstMatch(pending); end != null; end = _sentenceEnd.firstMatch(pending)) {
        final sentence = pending.substring(0, end.end);
        pending = pending.substring(end.end);
        final screened = s.pass(sentence);
        if (screened != sentence) {
          if (screened.isNotEmpty) {
            shown = true;
            yield screened;
          }
        } else if (!_bad(sentence, checkIn)) {
          shown = true;
          yield sentence;
        } else if (!shown && !last) {
          again = true;
          break;
        } // else left out
      }
      if (again) break;  // stops the generation; nothing of this try was shown
    }
    if (again) continue;
    final screened = pending.trim().isEmpty ? pending : s.pass(pending);
    if (screened != pending) {
      if (screened.isNotEmpty) {
        shown = true;
        yield screened;
      }
    } else if (pending.trim().isNotEmpty && !_bad(pending, checkIn)) {
      shown = true;
      yield pending;
    } else if (!shown && !last) {
      continue;
    }
    if (!shown) yield fallbackOpening;
    return;
  }
}

/// A reply sentence without em or en dashes (owner, 2026-11-19: "remove em dashes in its responses as it is not used
/// when communicating with humans and sounds so robotic"). A dash between two numbers becomes "to" ("5–10" -> "5 to
/// 10"); a dash that sets words apart becomes a comma ("tired — and" -> "tired, and"); a dash at the start or the end
/// of a sentence goes. Hyphens in words ("well-being") are kept. Every reply sentence passes here (ReplyScreen.pass).
String withoutDashes(String sentence) {
  if (!sentence.contains('—') && !sentence.contains('–')) return sentence;
  var s = sentence.replaceAllMapped(RegExp(r'(\d)\s*[–—]\s*(\d)'), (m) => '${m[1]} to ${m[2]}');
  s = s.replaceAll(RegExp(r'^\s*[–—]+\s*'), '');
  s = s.replaceAllMapped(RegExp(r'\s*[–—]+\s*([.!?…"”’)\]]|$)'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'\s*[–—]+\s*'), ', ');
  return s.replaceAll(RegExp(r',\s*,'), ',').replaceAll(RegExp(r'\s+,'), ',');
}

/// Every other reply, a sentence at a time: each passes [screen] first (ReplyScreen: a way or a means to die, or a
/// quote of the mode line, is replaced), then a sentence that names a mode is left out (namesMode).
Stream<String> withoutModeNames(Stream<String> pieces, {ReplyScreen? screen}) async* {
  final s = screen ?? ReplyScreen();
  String shown(String sentence) {
    final screened = s.pass(sentence);
    return screened != sentence || !namesMode(sentence) ? screened : '';
  }

  var pending = '';
  await for (final piece in pieces) {
    pending += piece;
    for (var end = _sentenceEnd.firstMatch(pending); end != null; end = _sentenceEnd.firstMatch(pending)) {
      final sentence = pending.substring(0, end.end);
      pending = pending.substring(end.end);
      final out = shown(sentence);
      if (out.isNotEmpty) yield out;
    }
  }
  if (pending.isNotEmpty) {
    final out = pending.trim().isEmpty ? pending : shown(pending);
    if (out.isNotEmpty) yield out;
  }
}
