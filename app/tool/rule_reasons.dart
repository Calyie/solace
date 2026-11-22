// ignore_for_file: avoid_print
// The phrase rules' level and reason for each line of a text file (one message per line). For tuning the rules.
// Usage: dart run tool/rule_reasons.dart LINES.txt [kind]
import 'dart:io';

import 'package:solace/core/safety.dart';

void main(List<String> args) {
  const check = SafetyCheck();
  final kind = args.length > 1 ? args[1] : 'daily_checkin';
  for (final line in File(args[0]).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final r = check.check(line, sessionKind: kind);
    print('${r.level.name.padRight(7)} ${r.reason.padRight(26)} ${r.plainlySafe ? 'P' : ' '} $line');
  }
}
