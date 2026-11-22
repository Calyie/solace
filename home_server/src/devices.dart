// The paired devices: at most four (one llama-server slot each), kept in devices.json at mode 600 with each device's
// id, the name the phone gave, the day it paired, its slot and the SHA-256 of its token. The token itself is never
// written on the server: a copy of this file lets no one make requests. A device keeps its slot for as long as it is
// paired (H19-17: the slot used to be its place in the list, so removing one device moved the later ones into slots
// that still held another device's conversation until llama-server restarted).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../app/home/home_protocol.dart';
import 'config.dart';

class PairedDevice {
  PairedDevice({required this.id, required this.name, required this.tokenSha, required this.paired, this.slot = -1});
  final String id, name, tokenSha, paired;

  /// Its llama-server slot, 0 to 3, fixed while it is paired (-1 only while a list from an older version is read).
  int slot;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'token_sha256': tokenSha, 'paired': paired, 'slot': slot};

  static PairedDevice? from(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], sha = j['token_sha256'], paired = j['paired'], slot = j['slot'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{8,32}$').hasMatch(id)) return null;
    if (name is! String || name.length > 64 || sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    return PairedDevice(id: id, name: name, tokenSha: sha, paired: paired is String && paired.length <= 10 ? paired : '',
        slot: slot is int && slot >= 0 && slot < maxDevices ? slot : -1);
  }
}

class DeviceStore {
  DeviceStore(this.file);

  /// No file: kept in memory only (the tests).
  DeviceStore.memory() : file = null;

  final File? file;
  final List<PairedDevice> _devices = [];

  List<PairedDevice> get devices => List.unmodifiable(_devices);

  Future<void> load() async {
    _devices.clear();
    final f = file;
    if (f == null || !await f.exists()) return;
    await makePrivate(f.path, 0x180); // a list copied in by hand is made private too, or refused (H19-18)
    if (await f.length() > 65536) throw const FormatException('devices.json is damaged (too large)');
    final j = jsonDecode(await f.readAsString());
    final list = j is Map ? j['devices'] : null;
    if (list is! List) throw const FormatException('devices.json is damaged');
    for (final e in list) {
      final d = PairedDevice.from(e);
      if (d != null && _devices.length < maxDevices && !_devices.any((x) => x.id == d.id)) _devices.add(d);
    }
    // a slot given twice, or none (a list from an older version): the later device takes the lowest free one
    final taken = <int>{};
    for (final d in _devices) {
      if (d.slot >= 0 && taken.add(d.slot)) continue;
      d.slot = -1;
    }
    for (final d in _devices) {
      if (d.slot < 0) taken.add(d.slot = _freeSlot(taken));
    }
  }

  /// The lowest slot not in [taken].
  static int _freeSlot(Set<int> taken) {
    var i = 0;
    while (taken.contains(i)) {
      i++;
    }
    return i;
  }

  /// How many slots llama-server needs so that every device's fixed slot exists: the highest slot in use, plus one
  /// (at least one, so the model is loaded and ready for the first pairing).
  int get slotsNeeded => _devices.isEmpty ? 1 : _devices.map((d) => d.slot).reduce(max) + 1;

  Future<void> _save() async {
    final f = file;
    if (f == null) return;
    await writePrivate(f, const JsonEncoder.withIndent('  ').convert({
      'devices': [for (final d in _devices) d.toJson()],
    }));
  }

  /// The device whose token is [token], or null. Every stored hash is compared, in constant time.
  PairedDevice? byToken(String token) {
    final sha = tokenHash(token);
    PairedDevice? found;
    for (final d in _devices) {
      if (sameText(d.tokenSha, sha)) found = d;
    }
    return found;
  }

  /// The slot of [d] (0 to 3), fixed while it is paired; -1 when it is no longer paired.
  int slotOf(PairedDevice d) {
    for (final x in _devices) {
      if (x.id == d.id) return x.slot;
    }
    return -1;
  }

  bool get full => _devices.length >= maxDevices;

  /// Adds a device named [name] and returns it with its new token (shown once, to the phone).
  Future<(PairedDevice, String)> add(String name, Random random) async {
    if (full) throw StateError('full');
    final token = randomText(random, 32);
    final now = DateTime.now().toUtc();
    final d = PairedDevice(id: randomText(random, 12), name: cleanName(name), tokenSha: tokenHash(token),
        paired: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        slot: _freeSlot({for (final x in _devices) x.slot}));
    _devices.add(d);
    try {
      await _save();
    } catch (_) {
      _devices.remove(d);
      rethrow;
    }
    return (d, token);
  }

  /// Removes the device [id]; true when there was one.
  Future<bool> remove(String id) async {
    final i = _devices.indexWhere((d) => d.id == id);
    if (i < 0) return false;
    final d = _devices.removeAt(i);
    try {
      await _save();
    } catch (_) {
      _devices.insert(i, d);
      rethrow;
    }
    return true;
  }
}

/// A device name as kept: printable characters only, at most 64.
String cleanName(String name) {
  final s = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  if (s.isEmpty) return 'a device';
  return s.length > 64 ? s.substring(0, 64) : s;
}
