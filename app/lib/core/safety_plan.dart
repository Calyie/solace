// A safety plan (research report P0 4): a short written plan for hard moments, made while the person feels steadier,
// worked down one step at a time until they feel safe. The steps follow the Safety Planning Intervention of Stanley
// and Brown (Cognitive and Behavioral Practice, 2012), the most studied brief intervention for suicide risk, written
// here in our own words (their template's wording is copyrighted). The country's crisis lines are always part of it.
// It lives in the encrypted store with everything else, and leaves Solace only as a file the person chooses to save.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'clinician_pdf.dart' show pdfText;
import 'crisis.dart';

/// One step of the plan: its id in the store, its title, what to write, and an example.
class PlanStep {
  const PlanStep(this.id, this.title, this.hint, this.example);
  final String id, title, hint, example;
}

const planSteps = <PlanStep>[
  PlanStep('signs', 'Signs a hard moment is building',
      'Thoughts, feelings, situations or things you do that tell you it is starting.', 'Not sleeping, pulling away'),
  PlanStep('alone', 'Things I can do on my own to feel steadier',
      'Small things that take your mind off it for a while.', 'A walk, a hot shower, the breathing practice'),
  PlanStep('distract', 'People and places that help me take my mind off things',
      'Where you can be around others without having to talk about it.', 'The library, my neighbour'),
  PlanStep('people', 'People I can ask for help', 'Their name and number.', 'Sam, 087 123 4567'),
  PlanStep('professionals', 'Professionals I can contact',
      'Your GP, therapist or care team, with their numbers. Your crisis lines are added below.', 'Dr Byrne, 01 234 5678'),
  PlanStep('safer', 'Making where I am safer',
      'Things you can do to keep yourself safe, like putting things away or asking someone to keep them for now.',
      'Ask my sister to keep my tablets'),
  PlanStep('reasons', 'What matters most to me',
      'The people, animals, plans and things that are worth staying for.', 'My dog, Lily'),
];

class SafetyPlan {
  SafetyPlan({Map<String, List<String>>? steps, this.updated}) : steps = steps ?? {};
  final Map<String, List<String>> steps;
  String? updated; // ISO date of the last change

  List<String> of(String id) => steps[id] ?? const [];
  bool get isEmpty => steps.values.every((v) => v.isEmpty);

  void add(String id, String text, String today) {
    final t = text.trim();
    if (t.isEmpty || of(id).contains(t)) return;
    (steps[id] ??= []).add(t);
    updated = today;
  }

  void remove(String id, int index, String today) {
    final list = steps[id];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    updated = today;
  }

  Map<String, dynamic> toJson() => {'steps': steps, 'updated': updated};

  factory SafetyPlan.fromJson(Map<String, dynamic>? j) {
    final raw = j?['steps'];
    final known = {for (final s in planSteps) s.id};
    return SafetyPlan(
      steps: raw is Map ? {
        for (final e in raw.entries)
          if (known.contains(e.key) && e.value is List) e.key as String: [for (final x in e.value as List) '$x'],
      } : {},
      updated: j?['updated'] as String?,
    );
  }
}

/// The plan as plain text, with the crisis lines of [country] in step 5.
String safetyPlanText(SafetyPlan plan, CountryCrisis? country) {
  final b = StringBuffer('My safety plan\n\nWork down the steps until you feel safe.\n');
  for (var i = 0; i < planSteps.length; i++) {
    final step = planSteps[i];
    b.write('\n${i + 1}. ${step.title}\n');
    final items = plan.of(step.id);
    for (final x in items) {
      b.write('   - $x\n');
    }
    if (step.id == 'professionals' && country != null) {
      for (final l in [...country.lines, ...country.emergency]) {
        b.write('   - ${l.name}: ${l.number}\n');
      }
    } else if (items.isEmpty) {
      b.write('   (nothing yet)\n');
    }
  }
  return b.toString();
}

/// The plan as a one-page PDF to print or keep, always on light paper. [regular] and [bold] are the bundled fonts.
Future<Uint8List> safetyPlanPdf(SafetyPlan plan, CountryCrisis? country, {ByteData? regular, ByteData? bold,
    int accent = 0xFF1D5BD8}) async {
  final theme = regular == null ? pw.ThemeData.base()
      : pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: bold == null ? null : pw.Font.ttf(bold));
  final ink = PdfColor.fromInt(0xFF0B1B33), muted = PdfColor.fromInt(0xFF5A6A84), hair = PdfColor.fromInt(0xFFD9D6CE);
  final colour = PdfColor.fromInt(accent);
  final doc = pw.Document(title: 'My safety plan', creator: 'Solace', producer: 'Solace');
  final body = pw.TextStyle(fontSize: 10.5, color: ink, lineSpacing: 2);
  pw.Widget stepBlock(int n, PlanStep step) {
    final items = [
      ...plan.of(step.id),
      if (step.id == 'professionals' && country != null)
        for (final l in [...country.lines, ...country.emergency]) '${l.name}: ${l.number}',
    ];
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: hair, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('$n. ${step.title}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: colour)),
        pw.SizedBox(height: 4),
        if (items.isEmpty) pw.Text(' ', style: body),
        for (final x in items) pw.Bullet(text: pdfText(x), style: body),
      ]),
    );
  }

  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (_) => [
      pw.Text('My safety plan', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ink)),
      pw.SizedBox(height: 4),
      pw.Text('Work down the steps until you feel safe. If you are in danger, call your emergency number now.',
          style: pw.TextStyle(fontSize: 10, color: muted)),
      pw.SizedBox(height: 14),
      for (var i = 0; i < planSteps.length; i++) stepBlock(i + 1, planSteps[i]),
      pw.SizedBox(height: 6),
      pw.Text('Made in Solace. The steps follow the Safety Planning Intervention (Stanley and Brown, 2012).',
          style: pw.TextStyle(fontSize: 8, color: muted)),
    ],
  ));
  return doc.save();
}
