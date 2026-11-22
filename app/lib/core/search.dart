// Search through older sessions and the journal (owner's v1 list): everything stays on the device. Each session
// (its words and its note) and each journal entry is one document, ranked by BM25 with a small lift for recent
// ones. A word also finds its longer forms ("drink" finds "drinking"), accents do not matter ("cafe" finds "Café"),
// and "words in quotes" must appear together. Each hit carries the best line, trimmed around the match, with the
// matched spans for highlighting.
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'store.dart';

class SearchHit {
  SearchHit({required this.date, required this.source, required this.snippet, required this.highlights,
      required this.score, this.index = -1});
  final String date; // ISO date
  final String source; // the session kind (weekly_session, daily_checkin, ...) or 'journal'
  final int index; // its place in AppData.sessions, or in AppData.journal for 'journal', so the screen can open it
  final String snippet;
  final List<(int, int)> highlights; // [start, end) in snippet
  final double score;
}

const _fold = {'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e',
  'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'o', 'æ': 'a', 'ị': 'i', 'ọ': 'o', 'ụ': 'u',
  'ṅ': 'n', '’': "'"};

/// [_fold] by UTF-16 code unit: every key and value above is one code unit.
final Map<int, int> _foldUnits = {for (final e in _fold.entries) e.key.codeUnitAt(0): e.value.codeUnitAt(0)};

/// Lower case without accents, the same length as the lower-cased input, so positions map back to the original text.
/// One pass over the code units (round 9 review B, 9B-01: the old split('')/map/join made a string per character).
String foldText(String s) {
  final units = s.toLowerCase().codeUnits;
  final out = Uint16List(units.length);
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    out[i] = _foldUnits[u] ?? u;
  }
  return String.fromCharCodes(out);
}

final _word = RegExp(r"[a-z0-9]+(?:'[a-z]+)?");

List<String> _tokens(String folded) => [for (final m in _word.allMatches(folded)) m.group(0)!];

/// One searchable document as plain values (a session's words and note, or a journal entry), so it can be handed to a
/// background isolate.
typedef SearchDocInput = ({String date, String source, int index, List<String> lines});

/// The documents of [data], in the order the hits refer to (sessions, then the journal). Cheap: it only gathers the
/// strings the store already holds.
List<SearchDocInput> searchInputs(AppData data) => [
      for (final (i, s) in data.sessions.indexed)
        (date: s.date, source: s.kind, index: i,
         lines: [for (final (_, x) in s.turns) x, ...s.note.split('\n').where((l) => l.trim().isNotEmpty)]),
      for (final (i, j) in data.journal.indexed) (date: '${j['date']}', source: 'journal', index: i, lines: ['${j['text']}']),
    ];

/// A key that changes when the searchable content of [data] is likely to have changed (a session or journal entry
/// added, removed or replaced), without reading the text. The memory search screen rebuilds its index when it changes.
Object searchKey(AppData data) => (
      identityHashCode(data), data.sessions.length, data.journal.length,
      data.sessions.isEmpty ? 0 : identityHashCode(data.sessions.last),
      data.journal.isEmpty ? 0 : identityHashCode(data.journal.last),
      data.sessions.isEmpty ? 0 : data.sessions.last.turns.length,
    );

/// The most of a query a search reads (round 9 review B, 9B-10): its first [maxQueryChars] characters, and of those its
/// first [maxQueryWords] distinct words and [maxQueryPhrases] quoted phrases, so a pasted paragraph costs about what a
/// short query does. The screen says when a query was cut ([queryIsCut]).
const maxQueryChars = 200, maxQueryWords = 12, maxQueryPhrases = 4;

/// The phrases and the distinct words a search reads of [query], in the order written, within the limits above.
(List<String>, List<String>) _queryParts(String query) {
  final fq = foldText(query.length > maxQueryChars ? query.substring(0, maxQueryChars) : query);
  final phrases = [for (final m in RegExp(r'"([^"]+)"').allMatches(fq)) m.group(1)!.trim()]..removeWhere((p) => p.isEmpty);
  // a quote is not part of a word, so the words of the whole query are those outside the phrases and inside them
  final words = _tokens(fq).toSet().take(maxQueryWords).toList();
  return (phrases.take(maxQueryPhrases).toList(), words);
}

/// True when [query] is longer than what a search reads (see [maxQueryChars]).
bool queryIsCut(String query) {
  if (query.length > maxQueryChars) return true;
  final fq = foldText(query);
  return _tokens(fq).toSet().length > maxQueryWords ||
      RegExp(r'"([^"]+)"').allMatches(fq).where((m) => m.group(1)!.trim().isNotEmpty).length > maxQueryPhrases;
}

/// The folded and tokenised documents, built once (round 9 review B, 9B-01), with an inverted index from each word to
/// the documents that hold it, so a query reads only the vocabulary and the matching documents instead of folding and
/// tokenising the whole store again. The vocabulary is kept sorted too, so the longer forms of a query word are one
/// range found by halving rather than a pass over every word (9B-10).
class SearchIndex {
  SearchIndex._(this._docs, this._postings, this._avg) : _vocab = _postings.keys.toList()..sort();

  factory SearchIndex.build(List<SearchDocInput> inputs) {
    final docs = <_Doc>[];
    final postings = <String, Map<int, int>>{}; // word -> {document: count}
    var total = 0;
    for (final d in inputs) {
      final folded = [for (final l in d.lines) foldText(l)];
      final n = docs.length;
      var count = 0;
      for (final l in folded) {
        for (final m in _word.allMatches(l)) {
          final w = m.group(0)!;
          final p = postings[w] ??= <int, int>{};
          p[n] = (p[n] ?? 0) + 1;
          count++;
        }
      }
      total += count;
      docs.add(_Doc(d.date, d.source, d.index, d.lines, folded, count));
    }
    return SearchIndex._(docs, postings, docs.isEmpty ? 0 : total / docs.length);
  }

  final List<_Doc> _docs;
  final Map<String, Map<int, int>> _postings;
  final List<String> _vocab; // the words of [_postings], sorted
  final double _avg;

  int get length => _docs.length;

  /// The words of the index that start with [q], in order: the first at or after [q], then on while they start with it.
  Iterable<String> _startingWith(String q) sync* {
    var lo = 0, hi = _vocab.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_vocab[mid].compareTo(q) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _vocab.length && _vocab[i].startsWith(q); i++) {
      yield _vocab[i];
    }
  }

  List<SearchHit> search(String query, {int limit = 30, DateTime? today}) {
    final (phrases, words) = _queryParts(query);
    if (words.isEmpty || _docs.isEmpty) return [];
    // per query word: the count of matching words in each document (a word matches itself, and its longer forms when
    // it has three letters or more), from the vocabulary rather than from every document
    final tfs = <Map<int, int>>[];
    for (final q in words) {
      final tf = <int, int>{};
      void add(Map<int, int> p) => p.forEach((doc, n) => tf[doc] = (tf[doc] ?? 0) + n);
      if (q.length < 3) {
        final p = _postings[q]; // short words match only themselves
        if (p != null) add(p);
      } else {
        for (final w in _startingWith(q)) {
          add(_postings[w]!);
        }
      }
      tfs.add(tf);
    }
    final candidates = <int>{for (final tf in tfs) ...tf.keys};
    // lines are searched with regular expressions, which scan text many times faster than String.contains (9B-10)
    final phraseIn = [for (final p in phrases) RegExp(RegExp.escape(p))];
    final anyWord = RegExp(words.map(RegExp.escape).join('|'));
    final now = today ?? DateTime.now();
    final scored = <(int, double)>[];
    for (final i in candidates) {
      final d = _docs[i];
      if (phraseIn.any((p) => !d.folded.any(p.hasMatch))) continue;
      var score = 0.0;
      for (var k = 0; k < words.length; k++) {
        final tf = tfs[k][i] ?? 0;
        if (tf == 0) continue;
        final df = tfs[k].length;
        final idf = log(1 + (_docs.length - df + 0.5) / (df + 0.5));
        score += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * d.count / max(_avg, 1)));
      }
      if (score == 0) continue;
      final age = now.difference(d.when ?? now).inDays.clamp(0, 3650);
      score *= 1 + 0.15 * exp(-age / 60); // a small lift for the last couple of months
      scored.add((i, score));
    }
    scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : _docs[b.$1].date.compareTo(_docs[a.$1].date));
    return [
      for (final (i, score) in scored.take(limit)) _hit(_docs[i], score, words, phrases, anyWord, phraseIn),
    ];
  }

  SearchHit _hit(_Doc d, double score, List<String> words, List<String> phrases, RegExp anyWord, List<RegExp> phraseIn) {
    // the best line: the most distinct query words, then the earliest
    var best = 0, bestCount = -1;
    for (var i = 0; i < d.folded.length; i++) {
      final line = d.folded[i];
      final n = _wordsIn(line, anyWord, words) + phraseIn.where((p) => p.hasMatch(line)).length;
      if (n > bestCount) {
        best = i;
        bestCount = n;
      }
    }
    final (snippet, spans) = _snippet(d.lines[best], d.folded[best], words, phrases);
    return SearchHit(date: d.date, source: d.source, snippet: snippet, highlights: spans, score: score, index: d.index);
  }
}

class _Doc {
  _Doc(this.date, this.source, this.index, this.lines, this.folded, this.count) : when = DateTime.tryParse(date);
  final String date, source;
  final DateTime? when; // [date] read once, not at every query (9B-10)
  final int index;
  final List<String> lines, folded;
  final int count; // its number of words
}

/// Builds the index away from the interface thread (round 9 review B, 9B-01). Replaced in widget tests
/// (test/flutter_test_config.dart), whose simulated clock cannot wait on another isolate.
Future<SearchIndex> Function(List<SearchDocInput> inputs) buildSearchIndexApart =
    (inputs) => Isolate.run(() => SearchIndex.build(inputs));

/// A query word matches a document word that is the same, or that starts with it when it has three letters or more.
bool _matches(String q, String w) => w == q || (q.length >= 3 && w.startsWith(q));

/// Whether [c] (a code unit of folded text) can be part of a word ([_word]).
bool _wordUnit(int c) => (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x27;

/// How many of the query [words] are in [line] as words, exactly as splitting the whole line with [_tokens] would find
/// them, but splitting only the runs of word characters where [anyWord] (any query word, anywhere) matched: a run is
/// bounded by characters no word holds, so it splits the same alone as inside the line (round 9 review B, 9B-10).
int _wordsIn(String line, RegExp anyWord, List<String> words) {
  final found = <String>{};
  var done = 0; // the runs before this have been read
  for (final m in anyWord.allMatches(line)) {
    if (m.start < done) continue;
    var start = m.start, end = m.end;
    while (start > 0 && _wordUnit(line.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < line.length && _wordUnit(line.codeUnitAt(end))) {
      end++;
    }
    for (final t in _word.allMatches(line.substring(start, end))) {
      final w = t.group(0)!;
      for (final q in words) {
        if (_matches(q, w)) found.add(q);
      }
    }
    done = end;
  }
  return found.length;
}

/// One search over [data] (builds the index each time; the screen keeps an index instead).
List<SearchHit> searchMemory(AppData data, String query, {int limit = 30, DateTime? today}) =>
    SearchIndex.build(searchInputs(data)).search(query, limit: limit, today: today);

(String, List<(int, int)>) _snippet(String line, String folded, List<String> words, List<String> phrases,
    {int width = 160}) {
  final spans = <(int, int)>[];
  for (final p in phrases) {
    for (var i = folded.indexOf(p); i >= 0; i = folded.indexOf(p, i + 1)) {
      spans.add((i, i + p.length));
    }
  }
  for (final m in _word.allMatches(folded)) {
    if (words.any((q) => _matches(q, m.group(0)!))) spans.add((m.start, m.end));
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  if (line.length <= width) return (line, spans);
  final first = spans.isEmpty ? 0 : spans.first.$1;
  var start = max(0, first - width ~/ 3);
  var end = min(line.length, start + width);
  start = max(0, end - width);
  final pre = start > 0 ? '…' : '', post = end < line.length ? '…' : '';
  final shift = pre.length - start;
  return (
    '$pre${line.substring(start, end)}$post',
    [for (final (a, b) in spans) if (a >= start && b <= end) (a + shift, b + shift)]
  );
}
