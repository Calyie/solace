// The safety classifier's tokenizer in Dart (STATUS T4): the Hugging Face BPE of its tokenizer.json (mmBERT, Gemma
// style: spaces become "▁", "▁" is put in front of each piece and the text is split before every "▁", characters
// outside the vocabulary fall back to their UTF-8 bytes, merges by rank, leftmost first). Every added token (the
// special ones such as "<bos>", and newline runs, "▁" runs, HTML tags) is cut out of the raw text first, leftmost and
// then longest, as the Python tokenizer does (a newline therefore starts a new piece: "\nnew" gives "▁new"). test/safety_classifier_test.dart checks
// it against the Python tokenizer, token for token, on 578 pairs (tests/make_safety_fixtures.py).
//
// To keep memory low on the phone it keeps only single-character entries and a sorted table of the 580,604 merges.
//
// No text can make it slow (OWASP review 2026-11-14, OW-A06-2): the merges of one word cost time in proportion to
// the square of its length, so a word longer than [BpeTokenizer.maxWordChars] characters is merged in pieces of that
// size (one pasted 16,000-character "word" took 1.6 s, and 50,000 would have taken many seconds); and the app runs
// it in its own isolate ([BpeWorker]), never on the one that draws the screen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

class BpeTokenizer {
  BpeTokenizer._(this._chars, this._bytes, this._mergeKeys, this._mergeValues, this._added, this._addedRe, this._lstrip,
      this.bos, this.eos, this.unk);

  static const _bits = 18; // token ids are below 2^18 (vocabulary 256,000)
  static const _mask = (1 << _bits) - 1;

  final Map<String, int> _chars;
  final List<int?> _bytes; // "<0x00>" .. "<0xFF>"
  final Int64List _mergeKeys; // (left << 18 | right), sorted
  final Int64List _mergeValues; // (rank << 18 | merged id)
  final Map<String, int> _added; // every added token, special or not
  final RegExp _addedRe; // leftmost, then longest
  final List<String> _lstrip; // the added tokens that take the whitespace before them, longest first
  final int bos, eos, unk;

  /// Builds the tokenizer from the text of tokenizer.json (run it in an isolate: the file is 34 MB).
  factory BpeTokenizer.fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final model = j['model'] as Map<String, dynamic>;
    final vocab = (model['vocab'] as Map<String, dynamic>).cast<String, int>();
    final chars = <String, int>{};
    final bytes = List<int?>.filled(256, null);
    for (final e in vocab.entries) {
      if (e.key.runes.length == 1) chars[e.key] = e.value;
      final m = RegExp(r'^<0x([0-9A-F]{2})>$').firstMatch(e.key);
      if (m != null) bytes[int.parse(m.group(1)!, radix: 16)] = e.value;
    }
    final merges = model['merges'] as List;
    final pairs = <List<int>>[];
    for (var rank = 0; rank < merges.length; rank++) {
      final m = merges[rank];
      final parts = m is List ? m.cast<String>() : (m as String).split(' ');
      final a = vocab[parts[0]], b = vocab[parts[1]], merged = vocab[parts[0] + parts[1]];
      if (a == null || b == null || merged == null) continue;
      pairs.add([(a << _bits) | b, (rank << _bits) | merged]);
    }
    pairs.sort((x, y) => x[0].compareTo(y[0]));
    final keys = Int64List(pairs.length), values = Int64List(pairs.length);
    for (var i = 0; i < pairs.length; i++) {
      keys[i] = pairs[i][0];
      values[i] = pairs[i][1];
    }
    final tokens = (j['added_tokens'] as List).cast<Map<String, dynamic>>()
      ..sort((x, y) => (y['content'] as String).length.compareTo((x['content'] as String).length));
    final added = {for (final t in tokens) t['content'] as String: t['id'] as int};
    // lstrip (only "<mask>" here) takes the whitespace before it into the token, as Python does. encode() does that
    // by hand: as "\s*<mask>" in the pattern it made a long run of spaces cost the square of its length (12,000 spaces
    // took a second; OW-A06-2), and the pattern is now plain text, so finding the tokens takes linear time.
    final re = RegExp(tokens.map((t) => RegExp.escape(t['content'] as String)).join('|'));
    final lstrip = [for (final t in tokens) if (t['lstrip'] == true) t['content'] as String];
    return BpeTokenizer._(chars, bytes, keys, values, added, re, lstrip, added['<bos>']!, added['<eos>']!,
        added['<unk>']!);
  }

  /// The characters "\s" matches in a Dart pattern.
  static bool _space(int c) => (c >= 0x09 && c <= 0x0D) || c == 0x20 || c == 0xA0 || c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 ||
      c == 0xFEFF;

  /// The ids of [text] with no special tokens added.
  List<int> encode(String text) {
    final out = <int>[];
    var last = 0, runEnd = -1;
    while (last < text.length) {
      final found = _addedRe.allMatches(text, last).iterator;
      if (!found.moveNext()) break;
      final m = found.current;
      var start = m.start, end = m.end, token = m[0]!;
      if (end == start) break; // no added token is empty; never loop on one that is
      // What "\s*T" (T an lstrip token) matched before: T, with the whitespace run before it back to the last token;
      // and a run of whitespace before T, rather than a whitespace token (newlines) inside that run, when the run
      // started before that token or T is the longer token (the pattern tried longer tokens first).
      if (_lstrip.isNotEmpty) {
        final isLstrip = _lstrip.contains(token);
        if (isLstrip || token.codeUnits.every(_space)) {
          var from = start;
          while (from > last && _space(text.codeUnitAt(from - 1))) {
            from--;
          }
          if (isLstrip) {
            start = from;
          } else {
            if (start >= runEnd) {
              runEnd = end;
              while (runEnd < text.length && _space(text.codeUnitAt(runEnd))) {
                runEnd++;
              }
            }
            for (final t in _lstrip) {
              if ((from < start || t.length > token.length) && text.startsWith(t, runEnd)) {
                start = from;
                end = runEnd + t.length;
                token = t;
                break;
              }
            }
          }
        }
      }
      if (start > last) _segment(text.substring(last, start), out);
      out.add(_added[token]!);
      last = end;
    }
    if (last < text.length) _segment(text.substring(last), out);
    return out;
  }

  void _segment(String text, List<int> out) {
    var s = text.replaceAll(' ', '▁');
    if (!s.startsWith('▁')) s = '▁$s';
    var start = 0;
    for (var i = 1; i < s.length; i++) {
      if (s.codeUnitAt(i) == 0x2581) {
        _word(s.substring(start, i), out);
        start = i;
      }
    }
    _word(s.substring(start), out);
  }

  /// The longest piece merged at once. Real words are far shorter; Python's tokenizer would merge across the cut, so
  /// only a "word" longer than this (a pasted run of letters, a long link) gets ids that differ from Python's.
  static const maxWordChars = 64;

  void _word(String word, List<int> out) {
    if (word.length <= maxWordChars) return _merged(word, out); // never more characters than UTF-16 units
    final runes = word.runes.toList();
    for (var i = 0; i < runes.length; i += maxWordChars) {
      _merged(String.fromCharCodes(runes, i, i + maxWordChars > runes.length ? runes.length : i + maxWordChars), out);
    }
  }

  void _merged(String word, List<int> out) {
    final syms = <int>[];
    for (final r in word.runes) {
      final ch = String.fromCharCode(r);
      final id = _chars[ch];
      if (id != null) {
        syms.add(id);
      } else {
        for (final b in utf8.encode(ch)) {
          syms.add(_bytes[b] ?? unk);
        }
      }
    }
    // pairs[i] is the merge of syms[i] and syms[i + 1] (rank << 18 | merged id), or -1: looked up once, and again
    // only beside each merge, so a piece costs one table lookup per merge instead of one per pair per merge. The
    // order is unchanged: the lowest rank first, the leftmost of equal ranks.
    final pairs = [for (var i = 0; i + 1 < syms.length; i++) _merge((syms[i] << _bits) | syms[i + 1])];
    while (pairs.isNotEmpty) {
      var bestRank = -1, bestPos = -1;
      for (var i = 0; i < pairs.length; i++) {
        final v = pairs[i];
        if (v < 0) continue;
        final rank = v >> _bits;
        if (bestPos < 0 || rank < bestRank) {
          bestRank = rank;
          bestPos = i;
        }
      }
      if (bestPos < 0) break;
      syms[bestPos] = pairs[bestPos] & _mask;
      syms.removeAt(bestPos + 1);
      pairs.removeAt(bestPos);
      if (bestPos > 0) pairs[bestPos - 1] = _merge((syms[bestPos - 1] << _bits) | syms[bestPos]);
      if (bestPos < pairs.length) pairs[bestPos] = _merge((syms[bestPos] << _bits) | syms[bestPos + 1]);
    }
    out.addAll(syms);
  }

  int _merge(int key) {
    var lo = 0, hi = _mergeKeys.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final k = _mergeKeys[mid];
      if (k == key) return _mergeValues[mid];
      if (k < key) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// The classifier's work for one message, in message tokens (round 6 review F, F6-11; before it, round 5 review,
  /// D-06). A full box of 12,000 characters, measured with the app's tokenizer (test/round6_classifier_budget_test.dart):
  /// English prose 2,738 tokens (11 windows), text speak 12, Russian 13, Polish 15, emoji 17, Arabic 17, Hindi 18,
  /// Greek 5,081 tokens (21 windows), a numeric mood log 8,306 (33). D-06 kept 12 windows, the most English prose
  /// makes, so up to 43 % of a full box of Greek and two thirds of the mood log were never read by the classifier. 24
  /// windows' worth (6,072 tokens) reads the whole of a full box of every ordinary language measured, and prose
  /// exactly as before (its 11 windows are under the budget); only text denser than that is cut, at twice the work of
  /// prose at most (D-06's concern: digits, combining marks or a script read a byte at a time made 48 windows, four
  /// times the work, 22 s on the laptop).
  static const tokenBudget = 24 * 253;

  /// The windows [tokenBudget] allows at the classifier's window size (256 tokens, 253 of them the message's).
  static const maxWindows = tokenBudget ~/ 253;

  /// The classifier's inputs for one message, as training paired them (train/safety_clf.py pair()): the last
  /// [contextChars] characters of the therapist's words, then the message: [bos] context [eos] message [eos], the
  /// context cut from its end to fit [maxLen] (truncation only_first). A message too long on its own is scored in
  /// consecutive windows without the context (tests/make_safety_fixtures.py); the risk is the highest window's.
  ///
  /// At most [maxWindowCount] windows are kept (by default as many as [tokenBudget] fills): for a message denser than
  /// that, the first window and the last ones (round 6 review F, F6-11: the beginning, where a message often says what
  /// matters most, and the end, where a paste ends and what the person wrote last sits; D-06 kept the end only), each
  /// window exactly as it would be with none dropped. The phrase rules still read the whole message.
    List<List<int>> windows(String context, String text,
      {int maxLen = 256, int contextChars = 300, int? maxWindowCount}) {
    // Python's context[-300:] counts characters, not UTF-16 units: an emoji is one character, never cut in half.
    final runes = context.runes.toList();
    final ctx = runes.length > contextChars ? String.fromCharCodes(runes.sublist(runes.length - contextChars)) : context;
    final a = ctx.isEmpty ? <int>[] : encode(ctx);
    if (text.isEmpty) return [[bos, ...a.take(maxLen - 2), eos]];
    final b = encode(text);
    final room = maxLen - 3;
    if (b.length <= room) return [[bos, ...a.take(room - b.length), eos, ...b, eos]];
    final count = (b.length + room - 1) ~/ room;
    final wanted = maxWindowCount ?? tokenBudget ~/ room;
    final keep = wanted < 1 ? 1 : wanted; // never no window at all: that would read as no risk
    List<int> window(int n) =>
        [bos, eos, ...b.sublist(n * room, (n + 1) * room > b.length ? b.length : (n + 1) * room), eos];
    if (count <= keep) return [for (var n = 0; n < count; n++) window(n)];
    if (keep == 1) return [window(count - 1)]; // the end, as before
    return [window(0), for (var n = count - keep + 1; n < count; n++) window(n)]; // the first, and the last ones
  }
}

/// The tokenizer in a long-lived isolate of its own (OWASP review 2026-11-14, OW-A06-2), as core/sherpa_voice.dart
/// keeps its voices: it is built there from tokenizer.json and stays there (the screen's isolate never holds its
/// merges), and each message becomes the classifier's windows there. A worker that has stopped, or a message that
/// takes longer than [timeout], is an error the caller sees (core/session.dart records a classifier fault and the
/// phrase rules, which have already read the message, stand); a request never waits forever.
class BpeWorker {
  BpeWorker._(this._isolate, this._toWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final _pending = <Completer<Object?>>{};
  bool _stopped = false;
  static const timeout = Duration(seconds: 10);

  /// Starts the worker on the tokenizer.json at [path]; throws when the file cannot be read or is not a tokenizer.
  static Future<BpeWorker> spawn(String path) async {
    final control = ReceivePort();
    final started = Completer<SendPort>();
    BpeWorker? worker;
    // the worker sends its port, or why it could not start (a String); null is its exit, whenever that comes
    control.listen((m) {
      if (m is SendPort && !started.isCompleted) return started.complete(m);
      if (!started.isCompleted) started.completeError(StateError(m is String ? m : 'the tokenizer worker stopped'));
      worker?._stop();
      control.close();
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_bpeWork, (control.sendPort, path), onExit: control.sendPort);
    } catch (_) {
      control.close();
      rethrow;
    }
    final port = await started.future;
    return worker = BpeWorker._(isolate, port);
  }

  void _stop() {
    _stopped = true;
    for (final c in _pending) {
      if (!c.isCompleted) c.completeError(StateError('the tokenizer worker stopped'));
    }
  }

  /// [BpeTokenizer.windows] of one message, made in the worker.
  Future<List<List<int>>> windows(String context, String text, {int maxLen = 256, int contextChars = 300}) async {
    if (_stopped) throw StateError('the tokenizer worker stopped');
    final done = Completer<Object?>();
    final reply = ReceivePort();
    _pending.add(done);
    reply.listen((m) {
      if (!done.isCompleted) done.complete(m);
    });
    try {
      _toWorker.send([context, text, maxLen, contextChars, reply.sendPort]);
      final answer = await done.future.timeout(timeout);
      if (answer is! List) throw StateError('$answer');
      return [for (final w in answer) (w as List).cast<int>()];
    } finally {
      _pending.remove(done);
      reply.close();
    }
  }

  void close() {
    _stop();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// The worker isolate: requests are [context, text, maxLen, contextChars, reply]; the answer is the windows, or
/// 'error: ...' rather than the worker stopping.
void _bpeWork((SendPort, String) start) {
  final (control, path) = start;
  final BpeTokenizer tok;
  try {
    tok = BpeTokenizer.fromJson(File(path).readAsStringSync());
  } catch (e) {
    control.send('error: the tokenizer could not be built (${e.runtimeType})');
    return;
  }
  final inbox = ReceivePort();
  control.send(inbox.sendPort);
  inbox.listen((message) {
    final r = message as List;
    final reply = r.last as SendPort;
    try {
      reply.send(tok.windows(r[0] as String, r[1] as String, maxLen: r[2] as int, contextChars: r[3] as int));
    } catch (e) {
      reply.send('error: ${e.runtimeType}');
    }
  });
}
