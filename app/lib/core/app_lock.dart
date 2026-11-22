// The app's own passcode, the app lock's only unlock on every device (owner, 2026-11-15): six digits, kept only as a
// salted Argon2id hash in the encrypted store, compared in constant time (as the deep work key is).
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

final _argon = Argon2id(memory: 19 * 1024, parallelism: 1, iterations: 2, hashLength: 32);

Future<Map<String, String>> hashPasscode(String code, {List<int>? salt}) async {
  final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final key = await _argon.deriveKey(secretKey: SecretKey(utf8.encode(code)), nonce: s);
  return {'salt': base64Encode(s), 'hash': base64Encode(await key.extractBytes())};
}

Future<bool> passcodeMatches(String code, Map<String, String> stored) async {
  final again = await hashPasscode(code, salt: base64Decode(stored['salt']!));
  final a = base64Decode(again['hash']!), b = base64Decode(stored['hash']!);
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

bool isPasscode(String code) => RegExp(r'^\d{6}$').hasMatch(code);
