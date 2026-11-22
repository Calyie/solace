// A summary a clinician can read (report recommendation 23), made on the device with the pdf package (pure Dart,
// Apache 2.0, no network): PHQ-9, GAD-7 and PCL-5 history with their bands and dates, a mood chart drawn in the PDF,
// programme progress, the named feelings, and only the notes the person ticks. It copies the pattern of Apple Health's
// PHQ-9/GAD-7 PDF and Daylio's export. Self-reported and labelled so: it is not a medical record or a diagnosis.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'dates.dart';
import 'emotions.dart';
import 'exports.dart';
import 'insights.dart' show windowDays;
import 'questionnaires.dart';
import 'store.dart';

/// Text the PDF's font can draw: emoji and joiners are left out (the bundled font has no pictures).
String pdfText(String s) => String.fromCharCodes(s.runes.where((r) =>
    r <= 0xFFFF && !(r >= 0x2600 && r <= 0x27BF) && r != 0xFE0F && r != 0x200D && !(r >= 0xD800 && r <= 0xDFFF)));

/// The bands of a questionnaire in words: "0 to 4 minimal, 5 to 9 mild, ...".
String bandKey(Questionnaire q) => [
      for (var i = 0; i < q.bands.length; i++)
        '${q.bands[i].$1} to ${i + 1 < q.bands.length ? q.bands[i + 1].$1 - 1 : q.maxScore} ${q.bands[i].$2}',
    ].join(', ');

/// The PDF as bytes. [regular] and [bold] are the bundled font files (Figtree); without them the PDF's own Helvetica
/// is used, which draws only basic Latin letters. [accent] is the app's primary colour (ARGB).
Future<Uint8List> clinicianPdf(AppData d, DateTime now, {Set<String> notes = const {}, ByteData? regular,
    ByteData? bold, int accent = 0xFF1D5BD8}) async {
  final theme = regular == null ? pw.ThemeData.base()
      : pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: bold == null ? null : pw.Font.ttf(bold));
  // paper is always light: the design's ink and slate (ui/theme.dart) whatever the app's own light or dark setting
  final ink = PdfColor.fromInt(0xFF0B1B33), muted = PdfColor.fromInt(0xFF5A6A84), hair = PdfColor.fromInt(0xFFD9D6CE);
  final colour = PdfColor.fromInt(accent);
  final doc = pw.Document(title: 'Wellbeing summary', subject: 'Self-reported wellbeing summary for a clinician',
      creator: 'Solace', producer: 'Solace');
  final small = pw.TextStyle(fontSize: 9, color: muted);
  final body = pw.TextStyle(fontSize: 10.5, color: ink, lineSpacing: 2);
  pw.Widget heading(String s) => pw.Padding(padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
      child: pw.Text(s, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: colour)));
  pw.Widget para(String s, {pw.TextStyle? style}) =>
      pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(pdfText(s), style: style ?? body));
  pw.Widget table(List<String> headers, List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: headers, data: [for (final r in rows) [for (final c in r) pdfText(c)]],
      headerStyle: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: ink),
      cellStyle: pw.TextStyle(fontSize: 9.5, color: ink), headerAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1EFEA)),
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: hair, width: 0.5),
          bottom: pw.BorderSide(color: hair, width: 0.5)));

  // the records behind each section
  final scores = scoreRows(d);
  final today = isoDate(now);
  final days = [for (var i = windowDays - 1; i >= 0; i--) isoDate(DateTime(now.year, now.month, now.day - i))];
  final rated = [for (var i = 0; i < days.length; i++) if (d.moods[days[i]] != null) (i, d.moods[days[i]]!)];
  final allDates = [...d.moods.keys, for (final s in scores) s.date, for (final e in d.emotions) e.date]..sort();
  final ticked = [for (final n in exportNotes(d)) if (notes.contains(n.id)) n]..sort((a, b) => a.date.compareTo(b.date));
  final recentFeelings = [for (final e in d.emotions) if (e.date.compareTo(days.first) >= 0) e];

  final content = <pw.Widget>[
    pw.Text('Wellbeing summary', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ink)),
    pw.SizedBox(height: 4),
    para('Prepared on ${longDate(today)} by the person themselves, from the records they keep in Solace, a private '
        'wellbeing app that works only on their own device. Everything here is self-reported. It is not a medical '
        'record or a diagnosis.', style: pw.TextStyle(fontSize: 10, color: muted, lineSpacing: 2)),
    if (allDates.isNotEmpty) para('Records from ${longDate(allDates.first)} to ${longDate(allDates.last)}.', style: small),

    heading('Questionnaires'),
    for (final q in questionnaires)
      if (scores.any((s) => s.q == q) || q != pcl5) ...[
        pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
            child: pw.Text(q.title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ink))),
        if (!scores.any((s) => s.q == q))
          para('No answers recorded.', style: small)
        else
          table([
            'Date', 'Score', 'Band',
            if (q.alertItem != null) 'Item ${q.alertItem! + 1}',
          ], [
            for (final s in scores)
              if (s.q == q) [
                longDate(s.date), '${s.total} of ${q.maxScore}', s.band,
                if (q.alertItem != null)
                  _item(q, s.items),
              ],
          ]),
        para('Bands: ${bandKey(q)}.${q.alertItem != null ? ' Item ${q.alertItem! + 1} asks about thoughts of being '
            'better off dead or of self-harm (0 not at all to 3 nearly every day).' : ''}', style: small),
      ],

    heading('Mood, last $windowDays days'),
    para('Self-rated once a day on a scale from 0 (very low) to 10 (very good). The latest rating of a day is kept.',
        style: small),
    if (rated.length < 2)
      para(rated.isEmpty ? 'No moods rated in this time.' : 'One mood rated in this time: ${rated.first.$2}.')
    else ...[
      pw.SizedBox(height: 170, child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis([0, 30, 60, windowDays - 1],
              format: (v) => dayMonthShort(days[v.toInt().clamp(0, windowDays - 1)]),
              textStyle: pw.TextStyle(fontSize: 8, color: muted), divisions: false, color: hair),
          yAxis: pw.FixedAxis([0, 2, 4, 6, 8, 10], format: (v) => '${v.toInt()}',
              textStyle: pw.TextStyle(fontSize: 8, color: muted), divisions: true, divisionsColor: hair,
              divisionsDashed: true, color: hair),
        ),
        datasets: [
          pw.LineDataSet(data: [for (final (x, y) in rated) pw.PointChartValue(x.toDouble(), y.toDouble())],
              color: colour, lineWidth: 1.5, pointSize: 2.2, drawSurface: true, surfaceOpacity: 0.12),
        ],
      )),
      pw.SizedBox(height: 6),
      para(_moodLine(rated.map((r) => r.$2).toList(), windowDays)),
    ],
    if (_monthly(d).length > 1) ...[
      pw.SizedBox(height: 6),
      table(['Month', 'Days rated', 'Average mood'], [
        for (final (month, n, mean) in _monthly(d)) [month, '$n', mean.toStringAsFixed(1)],
      ]),
    ],

    if (recentFeelings.isNotEmpty) ...[
      heading('Feelings named, last $windowDays days'),
      para(_feelingsLine(recentFeelings)),
    ],

    heading('Programme progress'),
    if (d.programmes.isEmpty) para('No programme started.', style: small),
    for (final p in d.programmes) ...[
      pw.Text(pdfText(p.name.isEmpty ? p.name : p.name[0].toUpperCase() + p.name.substring(1)),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ink)),
      pw.SizedBox(height: 3),
      for (final line in programmeLines(p, now)) para(line),
    ],

    heading('Notes the person chose to share'),
    if (ticked.isEmpty) para('None chosen. Notes are included only when the person ticks them.', style: small),
    for (final n in ticked) ...[
      pw.Text('${longDate(n.date)} (${n.source.toLowerCase()})',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: muted)),
      para(n.text),
      pw.SizedBox(height: 4),
    ],
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4, theme: theme, margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 40),
    footer: (context) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: hair, width: 0.5))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Wellbeing summary, self-reported, made with Solace', style: small),
        pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: small),
      ]),
    ),
    build: (_) => content,
  ));
  return doc.save();
}

/// The answer to a questionnaire's alert item, as a clinician reads it: "0 (Not at all)", or "not kept" for scores
/// saved without their answers.
String _item(Questionnaire q, List<int> items) {
  final i = q.alertItem!;
  if (items.length <= i || items[i] < 0 || items[i] >= q.options.length) return 'not kept';
  return '${items[i]} (${q.options[items[i]]})';
}

/// "26 Nov".
String dayMonthShort(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day} ${dayLabel(d).split(' ').last.substring(0, 3)}';
}

String _moodLine(List<int> values, int days) {
  final sorted = [...values]..sort();
  final mean = values.fold<int>(0, (a, b) => a + b) / values.length;
  return 'Rated on ${values.length} of $days days. Average ${mean.toStringAsFixed(1)}, lowest ${sorted.first}, '
      'highest ${sorted.last}.';
}

/// (month, days rated, average) for the last twelve months that have ratings, oldest first.
List<(String, int, double)> _monthly(AppData d) {
  final groups = <String, List<int>>{};
  for (final MapEntry(:key, :value) in d.moods.entries) {
    (groups[key.substring(0, 7)] ??= []).add(value);
  }
  final months = groups.keys.toList()..sort();
  const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
    'November', 'December'];
  return [
    for (final m in months.length > 12 ? months.sublist(months.length - 12) : months)
      ('${names[int.parse(m.substring(5)) - 1]} ${m.substring(0, 4)}', groups[m]!.length,
          groups[m]!.fold<int>(0, (a, b) => a + b) / groups[m]!.length),
  ];
}

String _feelingsLine(List<EmotionEntry> entries) {
  final words = <String, int>{}, tags = <String, int>{};
  for (final e in entries) {
    for (final w in e.words) {
      words[w] = (words[w] ?? 0) + 1;
    }
    for (final t in e.tags) {
      tags[t] = (tags[t] ?? 0) + 1;
    }
  }
  String top(Map<String, int> m, String Function(String) say) => (m.entries.toList()
        ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key)))
      .take(6).map((e) => '${say(e.key)} (${e.value})').join(', ');
  return 'Named ${entries.length} ${entries.length == 1 ? 'time' : 'times'}. Most often: ${top(words, (w) => w)}.'
      '${tags.isEmpty ? '' : ' What was affecting them: ${top(tags, (t) => tagLabel(t).toLowerCase())}.'}';
}
