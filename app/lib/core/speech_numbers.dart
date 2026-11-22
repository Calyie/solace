// Numbers said as words before the speech engine reads them (OW-M2-2, owner 2026-11-15: "Fix this too"). sherpa-onnx
// 2.x dropped espeak-ng, whose memory-safety bugs were the finding, and with it the part that turned digits into
// sounds: Kokoro speaks only words in its lexicons, so "116 123" or "3am" would be silent. English only, as the voices
// are; linear in the length (each rule is one pass with bounded patterns).

const _ones = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
  'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
const _ordinalOf = {'one': 'first', 'two': 'second', 'three': 'third', 'five': 'fifth', 'eight': 'eighth', 'nine': 'ninth',
  'twelve': 'twelfth'};

/// [n] (0 to 999,999,999) in words: 42 "forty two", 1005 "one thousand five".
String numberWords(int n) {
  if (n < 20) return _ones[n];
  if (n < 100) return n % 10 == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[n % 10]}';
  if (n < 1000) return n % 100 == 0 ? '${_ones[n ~/ 100]} hundred' : '${_ones[n ~/ 100]} hundred and ${numberWords(n % 100)}';
  for (final (size, name) in [(1000000, 'million'), (1000, 'thousand')]) {
    if (n >= size) {
      final rest = n % size;
      final head = '${numberWords(n ~/ size)} $name';
      return rest == 0 ? head : rest < 100 ? '$head and ${numberWords(rest)}' : '$head ${numberWords(rest)}';
    }
  }
  return _ones[0];
}

/// Digits one at a time ("116" "one one six"), for phone numbers and long codes.
String digitWords(String digits) => [for (final c in digits.split('')) if (_digit.hasMatch(c)) _ones[int.parse(c)]].join(' ');
final _digit = RegExp(r'^\d$');

String _ordinal(int n) {
  final w = numberWords(n);
  final parts = w.split(' ');
  final last = parts.last;
  final o = _ordinalOf[last] ?? (last.endsWith('y') ? '${last.substring(0, last.length - 1)}ieth' : '${last}th');
  return [...parts.sublist(0, parts.length - 1), o].join(' ');
}

String _year(int y) {
  if (y >= 2000 && y < 2010) return numberWords(y);
  final hi = y ~/ 100, lo = y % 100;
  return lo == 0 ? '${numberWords(hi)} hundred' : lo < 10 ? '${numberWords(hi)} oh ${_ones[lo]}' : '${numberWords(hi)} ${numberWords(lo)}';
}

final _longRun = RegExp(r'\d{16,}');
final _phone = RegExp(r'\+?\d(?:[ \-.]?\d){5,}');
final _time = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s?([ap])\.?m\b\.?', caseSensitive: false);
final _clock = RegExp(r'\b(\d{1,2}):(\d{2})\b');
final _percent = RegExp(r'(\d+(?:\.\d+)?)\s?%');
final _ordinalRe = RegExp(r'\b(\d{1,9})(st|nd|rd|th)\b', caseSensitive: false);
final _decimal = RegExp(r'\b(\d{1,9})\.(\d{1,6})\b');
final _grouped = RegExp(r'\b\d{1,3}(?:,\d{3})+\b');
final _yearRe = RegExp(r'\b(1[1-9]\d\d|20\d\d)\b');
final _integer = RegExp(r'\d+');

String _minutes(String m) {
  final v = int.parse(m);
  return v == 0 ? '' : v < 10 ? ' oh ${_ones[v]}' : ' ${numberWords(v)}';
}

/// [text] with its numbers in words: phone numbers and long codes digit by digit ("116 123" "one one six one two three"),
/// times ("3:30pm" "three thirty p m"), percentages, ordinals, decimals, years ("1999" "nineteen ninety nine") and
/// other whole numbers ("12" "twelve"). Numbers longer than nine digits are read digit by digit.
String spokenNumbers(String text) {
  if (!text.contains(RegExp(r'\d'))) return text;
  // a run of more than 15 digits is no number anyone says: it is "a long number", so a pasted wall of digits cannot
  // turn into minutes of speech (each digit would become a word)
  var t = text.replaceAll(_longRun, ' a long number ');
  t = t.replaceAllMapped(_phone, (m) {
    final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 6 ? ' ${digitWords(m[0]!)} ' : m[0]!;
  });
  t = t.replaceAllMapped(_time, (m) {
    final h = int.parse(m[1]!);
    if (h > 23) return m[0]!;
    return '${numberWords(h)}${m[2] == null ? '' : _minutes(m[2]!)} ${m[3]!.toLowerCase()} m';
  });
  t = t.replaceAllMapped(_clock, (m) {
    final h = int.parse(m[1]!);
    if (h > 23 || int.parse(m[2]!) > 59) return m[0]!;
    final mins = _minutes(m[2]!);
    return mins.isEmpty ? "${numberWords(h)} o'clock" : '${numberWords(h)}$mins';
  });
  t = t.replaceAllMapped(_percent, (m) => '${_decimalWords(m[1]!)} percent');
  t = t.replaceAllMapped(_ordinalRe, (m) => _ordinal(int.parse(m[1]!)));
  t = t.replaceAllMapped(_decimal, (m) => '${numberWords(int.parse(m[1]!))} point ${digitWords(m[2]!)}');
  t = t.replaceAllMapped(_grouped, (m) {
    final v = int.tryParse(m[0]!.replaceAll(',', ''));
    return v != null && v <= 999999999 ? numberWords(v) : digitWords(m[0]!);
  });
  t = t.replaceAllMapped(_yearRe, (m) => _year(int.parse(m[1]!)));
  t = t.replaceAllMapped(_integer, (m) => m[0]!.length <= 9 ? numberWords(int.parse(m[0]!)) : digitWords(m[0]!));
  t = t.replaceAll(RegExp(r' {2,}'), ' ');
  if (!text.startsWith(' ')) t = t.trimLeft();
  if (!text.endsWith(' ')) t = t.trimRight();
  return t;
}

String _decimalWords(String s) {
  final parts = s.split('.');
  final whole = parts[0].length <= 9 ? numberWords(int.parse(parts[0])) : digitWords(parts[0]);
  return parts.length == 1 ? whole : '$whole point ${digitWords(parts[1])}';
}
