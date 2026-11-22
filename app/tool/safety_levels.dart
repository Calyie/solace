// ignore_for_file: avoid_print
// The phrase rules' level for every message in a JSON list of strings, written as a JSON list of level names in the
// same order (none, concern, crisis, pause). For measuring the rules and the classifier together.
// Usage: dart run tool/safety_levels.dart IN.json OUT.json [kind]
import 'dart:convert';
import 'dart:io';

import 'package:solace/core/safety.dart';

void main(List<String> args) {
  const check = SafetyCheck();
  final kind = args.length > 2 ? args[2] : 'daily_checkin';
  final texts = (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<String>();
  final levels = [for (final t in texts) check.check(t, sessionKind: kind).level.name];
  File(args[1]).writeAsStringSync(jsonEncode(levels));
  print('${texts.length} messages: ${levels.where((l) => l == 'crisis').length} crisis, '
      '${levels.where((l) => l == 'concern').length} concern');
}
