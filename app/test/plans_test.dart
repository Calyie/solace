// The plans block must match the training code character for character, and notes must be read the same way:
// the references were made by pipeline/plans.py (tests/make_app_fixtures.py).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/plans.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/plans_$appPromptVersion.json').readAsStringSync()) as Map<String, dynamic>;
  final split = File('assets/prompts/app_split_v1.txt').readAsStringSync();

  for (final c in (fx['render'] as List).cast<Map>()) {
    test('plans block matches Python: ${c['name']}', () {
      final p = Plans.fromJson(Map<String, dynamic>.from(c['plans'] as Map));
      expect(p.asText(dayOf(c['today'] as String)), c['text']);
      expect(p.noticed(dayOf(c['today'] as String)), c['noticed']);
    });
    test('plans survive a save and load: ${c['name']}', () {
      final p = Plans.fromJson(jsonDecode(jsonEncode(Plans.fromJson(Map<String, dynamic>.from(c['plans'] as Map)).toJson())));
      expect(p.asText(dayOf(c['today'] as String)), c['text']);
    });
  }

  var k = 0;
  for (final c in (fx['apply'] as List).cast<Map>()) {
    test('items from a note are added exactly as in training (case ${k++})', () {
      final p = Plans.fromJson(Map<String, dynamic>.from(c['before'] as Map));
      final log = p.applyNote(parseNote(c['note'] as String).sections, dayOf(c['today'] as String), c['person'] as String);
      expect([for (final l in log) [l.heading, l.kind, l.item, l.quote, l.added, l.why]],
          [for (final l in (c['log'] as List).cast<Map>()) [l['heading'], l['kind'], l['item'], l['quote'], l['added'], l['why']]]);
      expect(jsonDecode(jsonEncode(p.toJson())), c['after']);
      expect(p.asText(dayOf(c['today'] as String)), c['text']);
    });
  }

  test('day and time words are read as in training', () {
    for (final w in (fx['when'] as List).cast<List>()) {
      expect(parseWhen(w[0] as String, dayOf(w[1] as String)), (w[2], w[3]), reason: '${w[0]} on ${w[1]}');
    }
  });

  test('a quote counts only if the person said it, as in training', () {
    for (final g in (fx['grounded'] as List).cast<List>()) {
      expect(grounded(g[0] as String, g[1] as String), g[2], reason: '"${g[0]}"');
    }
  });

  test('help me start: the instruction and the reader match training', () {
    expect(Prompts(system: '', note: '', story: '', split: split).splitInstruction('Lavoie details'), fx['split_instruction']);
    for (final s in (fx['split'] as List).cast<List>()) {
      expect([for (final (step, mins) in parseSplit(s[0] as String)) [step, mins]], s[1]);
    }
  });
}
