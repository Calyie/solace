// Review round 9 B, 9B-06: a transfer file of 180 KB opens to the 192 MB ceiling (core/transfer.dart maxOpenedBytes)
// and everything is decoded before anything refuses it: the opened bytes are turned into one Dart string
// (utf8.decode), then parsed into objects (jsonDecode), and only then do the 16 MB text limit and the picture checks
// run (here: 45 "pictures" of 4 MB of the letter A, under maxPhotoChars, which the picture check refuses as damaged
// after decoding each). Measured on this laptop: the process grows by about 550 MB for a 180 KB file. In the app
// this runs on a worker isolate of the same process, beside the loaded model (3.5 to 5.7 GB), so on a phone it is a
// plausible way to have the app killed for memory by a file the person was asked to import.
//
// The test asserts the SAFE behaviour: the file is refused and the process grows by less than 256 MB. It fails on
// 3d2da1f while the finding stands.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/transfer.dart';

/// gzip of `{"format":"solace_transfer","version":1,"app_data":{"photos":{"p0":"AAAA...", ...}}}` with [count]
/// pictures of [chars] characters each, made in pieces so the test itself never holds the opened text.
List<int> hostilePayload(int count, int chars) {
  final out = BytesBuilder(copy: false);
  final sink = ByteConversionSink.withCallback((b) => out.add(b));
  final z = gzip.encoder.startChunkedConversion(sink);
  final piece = utf8.encode('A' * 65536);
  z.add(utf8.encode('{"format":"solace_transfer","version":1,"app_data":{"photos":{'));
  for (var i = 0; i < count; i++) {
    z.add(utf8.encode('${i == 0 ? '' : ','}"p$i":"'));
    for (var left = chars; left > 0; left -= 65536) {
      z.add(left >= 65536 ? piece : piece.sublist(0, left));
    }
    z.add(utf8.encode('"'));
  }
  z.add(utf8.encode('}}}'));
  z.close();
  return out.takeBytes();
}

/// A sealed file in the transfer format (as TransferFile.seal writes it) around the gzip [payload], with [code].
Future<Uint8List> sealRaw(List<int> payload, String code) async {
  final salt = List<int>.filled(16, 7), nonce = List<int>.filled(12, 9);
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
      hashLength: 32).deriveKey(secretKey: SecretKey(utf8.encode(TransferCode.normalise(code))), nonce: salt);
  final box = await AesGcm.with256bits().encrypt(payload, secretKey: key, nonce: nonce, aad: h);
  return Uint8List.fromList([...h, ...box.cipherText, ...box.mac.bytes]);
}

void main() {
  test('9B-06: a small hostile transfer file does not make the opener hold hundreds of megabytes', () async {
    const code = '0123456789ABCDEF';
    // 45 pictures of just under 4 MB of text each (under maxPhotoChars, so the shape check passes): about 189 MB opened
    final file = await sealRaw(hostilePayload(45, 4 * 1024 * 1024 - 16), code);
    final fileKb = file.length ~/ 1024;
    final before = ProcessInfo.currentRss;
    Object? error;
    try {
      await TransferFile.open(file, code);
    } catch (e) {
      error = e;
    }
    final grew = (ProcessInfo.maxRss - before) ~/ (1024 * 1024);
    print('file $fileKb KB; refused: $error; peak memory grew by $grew MB');
    expect(error, isA<TransferError>());
    expect(grew, lessThan(256), reason: 'a $fileKb KB file made the opener grow by $grew MB before it was refused');
  });
}
