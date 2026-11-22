// ignore_for_file: avoid_print
// The phrase rules' level and plainly-safe reading (SafetyResult.plainlySafe, round 5 review D-05) for every message in a JSON
// list of strings, written as a JSON list of {"level": name, "plainlySafe": bool} in the same order. For measuring
// what the person meets once a plainly safe sentence no longer asks the classifier's question. Usage: dart run tool/safety_set_aside.dart IN.json OUT.json [kind]
import 'dart:convert';
import 'dart:io';

import 'package:solace/core/safety.dart';

void main(List<String> args) {
  const check = SafetyCheck();
  final kind = args.length > 2 ? args[2] : 'daily_checkin';
  final texts = (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<String>();
  final out = [
    for (final t in texts)
      () {
        final r = check.check(t, sessionKind: kind);
        return {'level': r.level.name, 'plainlySafe': r.plainlySafe};
      }()
  ];
  File(args[1]).writeAsStringSync(jsonEncode(out));
  print('${texts.length} messages: ${out.where((x) => x['plainlySafe'] == true).length} plainly safe');
}
