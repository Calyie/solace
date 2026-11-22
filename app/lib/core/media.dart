// References to pictures kept as separate encrypted files (Vault.putMedia), and the device's storage space, read
// through the app's own few lines of platform code (no package): Android StatFs, Apple's file-system attributes, and
// on Linux the standard df tool.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const mediaPrefix = 'media:';
bool isMediaRef(String v) => v.startsWith(mediaPrefix);
String mediaId(String ref) => ref.substring(mediaPrefix.length);

const _storage = MethodChannel('solace/storage');

/// Set by tests to stand in for the device's storage.
Future<(int, int)?> Function()? spaceForTests;

/// (total, free) bytes of the device's storage where Solace keeps its data, or null when it cannot be read.
Future<(int, int)?> readSpace() async {
  if (spaceForTests != null) return spaceForTests!();
  try {
    if (!kIsWeb && Platform.isLinux) {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return null; // never a real process in unit tests
      final home = Platform.environment['HOME'];
      if (home == null) return null;
      final r = await Process.run('df', ['-B1', '--output=size,avail', home]).timeout(const Duration(seconds: 3));
      final lines = '${r.stdout}'.trim().split('\n');
      if (lines.length < 2) return null;
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      return (int.parse(parts[0]), int.parse(parts[1]));
    }
    final m = await _storage.invokeMapMethod<String, Object?>('space');
    final total = m?['total'], free = m?['free'];
    if (total is int && free is int && total > 0) return (total, free);
  } catch (_) {}
  return null;
}
