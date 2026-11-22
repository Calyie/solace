// Makes the build-time fingerprint of the owner's Full mode key (lib/core/full_mode_key.dart). The key is six digits
// in <secrets>/therapist_full_mode_key.txt (owner, 2026-11-05: a random key until the owner puts the real one there);
// if that file is missing a random key is written to it, readable only by the owner's account. The key is never
// printed. Writes <secrets>/therapist_full_mode_key.json (salt and Argon2id fingerprint) for
//   flutter build ... --dart-define-from-file=<secrets>/therapist_full_mode_key.json
// Run again after changing the key, then rebuild. <secrets> is $THERAPIST_SECRETS or ~/htb-coae/cortec/.secrets.
//   dart run tool/full_mode_key.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:solace/core/full_mode_key.dart';

Future<void> main() async {
  final dir = Platform.environment['THERAPIST_SECRETS'] ?? '${Platform.environment['HOME']}/htb-coae/cortec/.secrets';
  final keyFile = File('$dir/therapist_full_mode_key.txt');
  final r = Random.secure();
  if (!keyFile.existsSync()) {
    keyFile.writeAsStringSync('${List.generate(6, (_) => r.nextInt(10)).join()}\n');
    await Process.run('chmod', ['600', keyFile.path]);
    stdout.writeln('No key yet: a random 6-digit key was written to ${keyFile.path} (not shown here).');
  }
  final key = keyFile.readAsStringSync().trim();
  if (!RegExp(r'^\d{6}$').hasMatch(key)) {
    stderr.writeln('${keyFile.path} must hold exactly six digits.');
    exit(1);
  }
  final salt = List<int>.generate(16, (_) => r.nextInt(256));
  final out = File('$dir/therapist_full_mode_key.json');
  out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'FULL_MODE_KEY_SALT': base64Encode(salt),
    'FULL_MODE_KEY_HASH': await FullModeKey.fingerprintOf(key, salt),
    'FULL_MODE_KEY_MEMORY': 65536,
    'FULL_MODE_KEY_ITERATIONS': 3,
  }));
  await Process.run('chmod', ['600', out.path]);
  stdout.writeln('Fingerprint written to ${out.path}. Build with --dart-define-from-file=${out.path}');
}
