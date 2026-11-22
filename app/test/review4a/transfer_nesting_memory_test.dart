// Review round 4, A: a small transfer file of deeply nested brackets passes every size cap and makes the opener build
// one Dart list per bracket before any value is counted (the reviver counts finished values only), so memory grows by
// about 60 bytes for every byte the cap allows (192 MB opened -> roughly 11-12 GB). Proof test: it failed on 5bdac57 and passes since the round 4 fix.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/transfer.dart';

/// A file built exactly as TransferFile.seal builds one (same header, same Argon2id settings, header as AAD), but with
/// [payload] as the gzip'd JSON inside: what anyone who knows the format and chooses the code can make.
Future<Uint8List> craft(List<int> payloadJson, String code) async {
  final r = Random(7);
  final salt = List<int>.generate(16, (_) => r.nextInt(256)), nonce = List<int>.generate(12, (_) => r.nextInt(256));
  final head = BytesBuilder()
    ..add(TransferFile.magic)
    ..addByte(TransferFile.version)
    ..addByte(1)
    ..add((ByteData(4)..setUint32(0, TransferFile.memoryKib)).buffer.asUint8List())
    ..addByte(TransferFile.iterations)
    ..addByte(TransferFile.parallelism)
    ..add(salt)
    ..add(nonce);
  final h = head.toBytes();
  final key = await Argon2id(parallelism: 1, memory: TransferFile.memoryKib, iterations: TransferFile.iterations,
          hashLength: 32)
      .deriveKey(secretKey: SecretKey(utf8.encode(TransferCode.normalise(code))), nonce: salt);
  final box = await AesGcm.with256bits().encrypt(gzip.encode(payloadJson), secretKey: key, nonce: nonce, aad: h);
  return Uint8List.fromList([...h, ...box.cipherText, ...box.mac.bytes]);
}

void main() {
  test('a tiny nested-bracket transfer file does not make the opener allocate gigabytes', () async {
    const code = '0123456789ABCDEF';
    const depth = 8 * 1000 * 1000; // 8 MB of "[" -- 4 percent of the 192 MB the opener allows
    final json = utf8.encode('{"format":"solace_transfer","app_data":{"journal":${'[' * depth}');
    final file = await craft(json, code);
    print('transfer file: ${file.length} bytes (cap ${TransferFile.maxFileBytes}); opens to ${json.length} bytes '
        '(cap ${TransferFile.maxOpenedBytes})');
    final before = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    Object? outcome;
    try {
      await TransferFile.openInBackground(file, code); // the screen's path: a worker isolate
    } catch (e) {
      outcome = e;
    }
    final grew = ProcessInfo.maxRss - before;
    print('refused after ${sw.elapsedMilliseconds} ms with ${outcome.runtimeType}: $outcome');
    print('peak memory grew by ${grew ~/ (1024 * 1024)} MB for a ${file.length ~/ 1024} KB file');
    expect(outcome, isA<TransferError>());
    // the caps promise at most ~128 MB in and 192 MB opened; 300 MB of growth is already well past them
    expect(grew, lessThan(300 * 1024 * 1024), reason: 'the value count never runs: no value finishes before memory');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
