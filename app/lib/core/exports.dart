// The person's own records as files they can keep or share (report recommendation 23): a spreadsheet (CSV) and a
// plain-text page (Markdown) of moods, named feelings and questionnaire scores. The clinician's PDF is in
// clinician_pdf.dart. Free-text notes go into a file only when the person ticks them. Once saved, a file is outside
// Solace's encryption; every screen that makes one says so.
import 'dates.dart';
import 'emotions.dart';
import 'formats.dart' show LogEntry;
import 'questionnaires.dart';
import 'store.dart';

/// A note the person may choose to include: their own words from a named-feeling check-in or the journal.
class ExportNote {
  const ExportNote({required this.id, required this.date, required this.source, required this.text});
  final String id; // stable within one export: 'feeling:<at>:<n>' or 'journal:<n>'
  final String date; // ISO date
  final String source; // what the person sees: 'Named feeling' or 'Journal'
  final String text;
}

/// Every note that could go into a file, newest first. None is included unless its id is ticked.
List<ExportNote> exportNotes(AppData d) {
  final notes = <ExportNote>[
    for (var i = 0; i < d.emotions.length; i++)
      if (d.emotions[i].note.trim().isNotEmpty)
        ExportNote(id: 'feeling:${d.emotions[i].at}:$i', date: d.emotions[i].date, source: 'Named feeling',
            text: d.emotions[i].note.trim()),
    for (var i = 0; i < d.journal.length; i++)
      if (d.journal[i]['date'] is String && '${d.journal[i]['text'] ?? ''}'.trim().isNotEmpty)
        ExportNote(id: 'journal:$i', date: d.journal[i]['date'] as String, source: 'Journal',
            text: '${d.journal[i]['text']}'.trim()),
  ];
  notes.sort((a, b) => b.date.compareTo(a.date));
  return notes;
}

/// "Thursday 26 November 2026".
String longDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${dayLabel(d)} ${d.year}';
}

/// The questionnaire answers, oldest first, each with its band.
List<({String date, Questionnaire q, int total, String band, List<int> items})> scoreRows(AppData d) {
  final rows = [
    for (final s in d.scores)
      for (final q in questionnaires)
        if (s['name'] == q.name && s['total'] is int && s['date'] is String)
          (date: s['date'] as String, q: q, total: s['total'] as int, band: q.band(s['total'] as int),
              items: [for (final x in (s['items'] is List ? s['items'] as List : const [])) if (x is int) x]),
  ];
  rows.sort((a, b) => a.date.compareTo(b.date));
  return rows;
}

/// One cell of a CSV file. A cell that a spreadsheet could read as a formula (starting with =, +, -, @ or a tab) is
/// written with a leading apostrophe, so opening the file can never run anything; commas, quotes and line breaks are
/// quoted as RFC 4180 says.
String csvCell(Object? value) {
  var s = '${value ?? ''}';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

const csvHeader = ['date', 'time', 'record', 'name', 'value', 'band', 'words', 'affecting', 'note'];

/// Moods, named feelings and questionnaire scores in one table, oldest first; ticked notes only.
String exportCsv(AppData d, {Set<String> notes = const {}}) {
  final rows = <List<Object?>>[
    for (final MapEntry(:key, :value) in d.moods.entries)
      [key, d.moodTimes[key] ?? '', 'mood', 'Mood (0 to 10)', value, '', '', '', ''],
    for (var i = 0; i < d.emotions.length; i++)
      [d.emotions[i].date, d.emotions[i].at.substring(11), 'feelings', quadrantTitle(d.emotions[i].quadrant), '', '',
        d.emotions[i].words.join('; '), [for (final t in d.emotions[i].tags) tagLabel(t)].join('; '),
        notes.contains('feeling:${d.emotions[i].at}:$i') ? d.emotions[i].note : ''],
    for (final r in scoreRows(d)) [r.date, '', 'questionnaire', r.q.name, r.total, r.band, '', '', ''],
    for (final n in exportNotes(d))
      if (n.source == 'Journal' && notes.contains(n.id)) [n.date, '', 'note', n.source, '', '', '', '', n.text],
  ];
  rows.sort((a, b) {
    final c = (a[0] as String).compareTo(b[0] as String);
    return c != 0 ? c : (a[1] as String).compareTo(b[1] as String);
  });
  // a byte-order mark first, so spreadsheet apps read accents and curly quotes correctly
  return '\uFEFF${[csvHeader, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

String _cell(String s) => mdText(s).replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');

/// Words from the records, made inert for a Markdown viewer (OWASP review, Info OW-I3): an export opened later must
/// never fetch anything or carry a working link, whatever the words are (a note, or text that came in a transfer
/// file). Backslashes, backticks and square brackets are escaped and "<" is written as "&lt;", so no picture, link,
/// link reference or HTML tag can form; a web address is shown as code, which no viewer turns into a link. A viewer
/// shows the words as typed.
String mdText(String s) {
  final out = StringBuffer();
  var last = 0;
  for (final m in _webAddress.allMatches(s)) {
    var end = m.end; // punctuation that ends the sentence stays outside the address, as viewers do
    while (end > m.start + 1 && '.,;:!?)\'"'.contains(s[end - 1])) {
      end--;
    }
    out
      ..write(_mdEscape(s.substring(last, m.start)))
      ..write('`${s.substring(m.start, end)}`');
    last = end;
  }
  out.write(_mdEscape(s.substring(last)));
  return out.toString();
}

// a web address with or without its scheme, up to anything that could end a code span or start markup
final _webAddress = RegExp(r'(?:\b[a-z][a-z0-9+.-]*://|\bwww\.)[^\s<>\[\]`\\]+', caseSensitive: false);
// an angle bracket becomes the entity, which every Markdown flavour leaves as text (some do not honour "\<")
String _mdEscape(String s) =>
    s.replaceAllMapped(RegExp(r'[\\`\[\]<]'), (m) => m[0] == '<' ? '&lt;' : '\\${m[0]}');

/// The same records as a page anyone can read in a text editor, newest first; ticked notes only.
String exportMarkdown(AppData d, DateTime now, {Set<String> notes = const {}}) {
  final out = StringBuffer()
    ..writeln('# My records from Solace')
    ..writeln()
    ..writeln('Exported on ${longDate(isoDate(now))}. Self-reported, from my own device. Once saved, this file is '
        "outside Solace's encryption.")
    ..writeln();
  final moods = d.moods.keys.toList()..sort((a, b) => b.compareTo(a));
  out
    ..writeln('## Mood (0 to 10)')
    ..writeln();
  if (moods.isEmpty) {
    out.writeln('No moods rated yet.');
  } else {
    out
      ..writeln('| Date | Time | Mood |')
      ..writeln('|---|---|---|');
    for (final m in moods) {
      out.writeln('| ${_cell(longDate(m))} | ${_cell(d.moodTimes[m] ?? '')} | ${d.moods[m]} |');
    }
  }
  out
    ..writeln()
    ..writeln('## Feelings named')
    ..writeln();
  if (d.emotions.isEmpty) out.writeln('No feelings named yet.');
  for (var i = d.emotions.length - 1; i >= 0; i--) {
    final e = d.emotions[i];
    final affecting = e.tags.isEmpty ? '' : ' Affecting: ${mdText([for (final t in e.tags) tagLabel(t).toLowerCase()].join(', '))}.';
    out.writeln('- **${mdText(longDate(e.date))}, ${mdText(e.at.substring(11))}**: '
        '${mdText(quadrantTitle(e.quadrant).toLowerCase())}; ${mdText(e.words.join(', '))}.$affecting');
    if (notes.contains('feeling:${e.at}:$i')) {
      for (final line in e.note.split(RegExp(r'\r?\n'))) {
        out.writeln('  > ${mdText(line)}');
      }
    }
  }
  final scores = scoreRows(d).reversed.toList();
  out
    ..writeln()
    ..writeln('## Questionnaires')
    ..writeln();
  if (scores.isEmpty) {
    out.writeln('No questionnaires answered yet.');
  } else {
    out
      ..writeln('| Date | Questionnaire | Score | Band |')
      ..writeln('|---|---|---|---|');
    for (final r in scores) {
      out.writeln('| ${_cell(longDate(r.date))} | ${_cell(r.q.name)} | ${r.total} of ${r.q.maxScore} | ${_cell(r.band)} |');
    }
    out
      ..writeln()
      ..writeln('Lower scores mean fewer difficulties. A questionnaire is a snapshot, not a diagnosis.');
  }
  final journal = [for (final n in exportNotes(d)) if (n.source == 'Journal' && notes.contains(n.id)) n];
  if (journal.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Notes I chose to include')
      ..writeln();
    for (final n in journal) {
      out.writeln('- **${mdText(longDate(n.date))}** (journal):');
      for (final line in n.text.split(RegExp(r'\r?\n'))) {
        out.writeln('  > ${mdText(line)}');
      }
    }
  }
  return out.toString();
}

/// What a programme has built up, in the same words as the Progress tab (ui/programmes.dart ProgrammeProgress).
List<String> programmeLines(Programme p, DateTime today) {
  final entries = [for (final (_, e) in p.log) e];
  final outcomes = entries.where((e) => e.type == 'outcome').toList();
  int count(String type) => entries.where((e) => e.type == type).length;
  bool about(LogEntry o, String type) => entries.any((e) => e.type == type && e.text == o.details['about']);
  int checked(String type) => outcomes.where((o) => about(o, type)).length;
  int answered(String type, String result) =>
      outcomes.where((o) => about(o, type) && o.details['result'] == result).length;
  return [
    'Started ${longDate(p.start)}; day ${p.dayOn(today)}, ${p.sessions} ${p.sessions == 1 ? 'session' : 'sessions'} done',
    if (checked('commitment') > 0) 'Commitments kept: ${answered('commitment', 'yes')}, partly '
        '${answered('commitment', 'partly')}, of ${checked('commitment')} checked',
    if (checked('prediction') > 0) 'Fears that came true: ${answered('prediction', 'yes')}, partly '
        '${answered('prediction', 'partly')}, of ${checked('prediction')} checked',
    if (checked('activity') > 0) 'Activities done: ${answered('activity', 'yes') + answered('activity', 'partly')} '
        'of ${checked('activity')} checked',
    if (count('evidence') > 0) 'Evidence collected: ${count('evidence')} pieces',
    if (checked('urge') > 0) 'Urges held off: ${answered('urge', 'yes') + answered('urge', 'partly')} of '
        '${checked('urge')} checked',
  ];
}
