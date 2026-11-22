// Before serving, the gateway checks the model exactly as the app checks a model on the device, with the app's own
// code (app/lib/core/model_manifest.dart, app/lib/core/trusted.dart): the GGUF's SHA-256 must match the .sha256 list
// beside it, and the model must be one this version of Solace trusts: built in (trustedModels), or on the owner's
// signed model list (solace-models.json and solace-models.json.sig beside the model, its signature checked against
// the public key built into the app before anything in it is read), made for this version of the app and not
// withdrawn. A model the maker did not sign is served only when the server's owner names its SHA-256 in
// accept_unsigned (and each phone still asks its own person, as for a model on the device). The phone checks the
// served model's SHA-256 again against its own lists before it uses it.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import '../../app/lib/core/model_manifest.dart';
import '../../app/lib/core/trusted.dart' show isTrustedModel;

class ServedModel {
  ServedModel({required this.file, required this.sha256, required this.size, required this.light,
      required this.trustedBy});
  final File file;
  final String sha256;
  final int size;
  final bool light;

  /// 'built-in', 'signed' or 'accepted' (named by the server's owner in accept_unsigned).
  final String trustedBy;

  String get name => file.uri.pathSegments.last;

  Map<String, Object> toJson() =>
      {'sha256': sha256, 'name': name, 'size': size, 'tier': light ? 'light' : 'standard', 'trusted_by': trustedBy};
}

class ModelRefused implements Exception {
  ModelRefused(this.why);
  final String why;
  @override
  String toString() => why;
}

/// Checks [gguf] and returns what is served, or throws [ModelRefused] with the reason in plain words.
Future<ServedModel> checkModel(File gguf, {List<String> acceptUnsigned = const []}) async {
  if (!await gguf.exists()) throw ModelRefused('The model file ${gguf.path} is not there.');
  final dir = gguf.parent, name = gguf.uri.pathSegments.last;
  final listed = <String>{};
  await for (final e in dir.list()) {
    if (e is! File || !e.path.endsWith('.sha256')) continue;
    if (await e.length() > 65536) continue;
    for (final line in await e.readAsLines()) {
      final m = RegExp(r'^([0-9a-f]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (m != null && m.group(2)!.split('/').last == name) listed.add(m.group(1)!);
    }
  }
  if (listed.isEmpty) throw ModelRefused('No .sha256 list beside the model names $name. Copy it with the model.');
  final size = await gguf.length();
  final sum = await sha256OfFile(gguf);
  if (!listed.contains(sum)) {
    throw ModelRefused('$name does not match its .sha256 list (it may be damaged or swapped). Copy it again.');
  }
  ModelList? list;
  final listFile = File('${dir.path}/solace-models.json'), sigFile = File('${dir.path}/solace-models.json.sig');
  if (await listFile.exists() && await sigFile.exists() && await listFile.length() <= maxModelListBytes &&
      await sigFile.length() <= maxSignatureBytes) {
    final (l, why) = await readModelList(await listFile.readAsBytes(), await sigFile.readAsBytes());
    if (l == null) throw ModelRefused('The signed model list beside the model was refused: $why');
    list = l;
  }
  final why = whyNotTrusted(sum, list, size: size, accepted: acceptUnsigned.toSet());
  if (why != null) {
    throw ModelRefused('$why (SHA-256 $sum)${acceptUnsigned.isEmpty && list?.models[sum] == null && !isTrustedModel(sum)
        ? '. A model the maker of Solace did not sign is served only when its SHA-256 is in accept_unsigned.' : ''}');
  }
  final trustedBy = isTrustedModel(sum) ? 'built-in' : list?.models[sum] != null ? 'signed' : 'accepted';
  final light = list?.models[sum]?.light ?? !(name.contains('e4b') || name.contains('standard'));
  return ServedModel(file: gguf, sha256: sum, size: size, light: light, trustedBy: trustedBy);
}

/// The SHA-256 of [f]: the system's sha256sum or shasum when there is one (several times faster on a 5 GB file),
/// else computed here.
Future<String> sha256OfFile(File f) async {
  for (final (tool, args) in [('sha256sum', <String>[]), ('shasum', ['-a', '256'])]) {
    try {
      final r = await Process.run(tool, [...args, f.path]);
      final m = RegExp(r'^([0-9a-f]{64})\s').firstMatch('${r.stdout}');
      if (r.exitCode == 0 && m != null) return m.group(1)!;
    } on ProcessException {
      // not on this system
    }
  }
  final path = f.path;
  return Isolate.run(() {
    final sink = const DartSha256().newHashSink();
    final raf = File(path).openSync();
    try {
      final buffer = Uint8List(8 << 20);
      for (var n = raf.readIntoSync(buffer); n > 0; n = raf.readIntoSync(buffer)) {
        sink.addSlice(buffer, 0, n, false);
      }
    } finally {
      raf.closeSync();
    }
    sink.close();
    return sink.hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
}
