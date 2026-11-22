// ignore_for_file: avoid_print
// Run the app's safety check over a file of lines (one message per line) and report how often it fires.
// Usage: dart run tool/safety_scan.dart LINES.txt [kind]
import 'dart:io';

import 'package:solace/core/safety.dart';

void main(List<String> args) {
  const check = SafetyCheck();
  final kind = args.length > 1 ? args[1] : 'daily_checkin';
  final lines = File(args[0]).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final hits = <String, List<String>>{};
  for (final l in lines) {
    final r = check.check(l, sessionKind: kind);
    if (r.level != SafetyLevel.none) (hits[r.reason] ??= []).add(l);
  }
  final n = hits.values.fold<int>(0, (a, b) => a + b.length);
  print('${lines.length} lines, $n flagged (${(100 * n / lines.length).toStringAsFixed(3)}%)');
  for (final e in hits.entries) {
    print('  ${e.key}: ${e.value.length}');
    for (final s in e.value.take(4)) {
      print('     - ${s.length > 150 ? s.substring(0, 150) : s}');
    }
  }
}
