// The practice library (assets/practices/library_v2.json, built by tool/build_library_v2.py).
import 'dart:convert';

class PracticeStep {
  const PracticeStep(this.text, this.pause, {this.pacer = false});
  final String text;
  final int pause; // seconds of silence after the step
  final bool pacer; // show and sound the breathing guide during the silence
}

class PracticeVersion {
  const PracticeVersion(this.minutes, this.steps);
  final int minutes;
  final List<PracticeStep> steps;
}

class Practice {
  const Practice({required this.id, required this.title, required this.category, required this.type,
      required this.when, this.versions = const {}, this.minutes = 0, this.practiceName = '', this.about = '',
      this.evidence = '', this.pacer = const []});
  final String id;
  final String title;
  final String category;
  final String type; // meditation, tool (both spoken) or interactive (opens a session)
  final String when;
  final Map<String, PracticeVersion> versions; // guided: short and/or long
  final int minutes; // interactive
  final String practiceName; // interactive: the name the session opens with
  final String about;
  final String evidence; // an honest one-line summary of the evidence
  final List<(String, int)> pacer; // breathing pattern: (label, seconds) phases

  bool get guided => type != 'interactive'; // meditations and tools are spoken; interactive ones open a session
  bool get meditation => type == 'meditation';

  factory Practice.fromJson(Map<String, dynamic> j) => Practice(
        id: j['id'], title: j['title'], category: j['category'], type: j['type'], when: j['when'] ?? '',
        minutes: j['minutes'] ?? 0, practiceName: j['practice_name'] ?? '', about: j['about'] ?? '',
        evidence: j['evidence'] ?? '',
        pacer: [for (final ph in (j['pacer'] as List? ?? [])) ((ph as List)[0] as String, ph[1] as int)],
        versions: {
          for (final e in ((j['versions'] as Map?) ?? {}).entries)
            e.key as String: PracticeVersion((e.value as Map)['minutes'] as int, [
              for (final s in (e.value as Map)['steps'] as List)
                PracticeStep(s['text'] as String, s['pause'] as int, pacer: s['pacer'] == true)
            ])
        },
      );
}

const categoryNames = <String, String>{
  'morning': 'Start the day', 'calm': 'Calm, fast', 'kindness': 'Kindness to yourself', 'direction': 'Direction',
  'let_go': 'Letting go', 'urges': 'Urges and habits', 'deep': 'Deep calm', 'sleep': 'Sleep',
  'feel_good': 'Feel good', 'safe': 'Feeling safe',
  'tools': 'With Solace',
};

List<Practice> parseLibrary(String json) =>
    [for (final p in jsonDecode(json) as List) Practice.fromJson(Map<String, dynamic>.from(p as Map))];
