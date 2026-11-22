// How much room Solace's own data may take (owner, 2026-11-14: the app's data must not impact the device or other
// apps; at a limit the person deletes older things, with room enough for a great deal; and they can keep a copy of
// whatever matters first). The model, voice and safety files are separate and fixed in size.
//
// The room is a fixed 2 GB, the same on every device (owner, 2026-11-19: "the app should not read the device memory and
// say the memory is full. That is private and should not be read or at least not reported"; until then it was 2
// percent of the device's storage, at most 2 GB, and Today and Settings also spoke of the device's own free space).
// Solace never reads the device's capacity or free space for any warning, card or Settings line; the one silent check
// left is before a model or the voice and safety bundle is copied in (ui/model_files.dart), so a copy never stops
// half-way, and it says only that there is not enough free space, with no numbers about the device. A conversation is
// about 10 to 20 KB and a picture, shrunk to card size when it is added, about half a megabyte, so this is room for
// tens of thousands of conversations or thousands of pictures. The conversation store itself also stays under 100 MB
// so that every save stays quick; pictures are kept apart from it. From 80 percent of Solace's own room the Today tab
// says so gently; at the limit a new conversation cannot start (off the record still can) and no picture is added
// until some room is made. Nothing already saved is ever deleted without the person choosing it.
//
// With the device's own space never read, the device can still fill up (other apps, or pictures taking its last free
// space), and then a save can fail. A failed save is never silent (H19-14): the banner at the top says so with Try
// again (AppState.saveProblem), a session's safety records say so quietly (SessionController.safetySaveFailing), and
// everything stays in memory and is written by the next save that works (the next safety record, reply, End, or Try
// again). Before a picture takes more room, the data and its safety records are saved first (AppState.setPicture). An
// import replaces the data whole, with no session open, so every safety record has had its own save by then; a failed
// save after it says "Brought in, but not saved on this device yet" (ui/transfer_screen.dart importNotSaved).
import 'dart:convert';
import 'dart:isolate';

import 'dates.dart';
import 'media.dart';
import 'store.dart';

/// Solace's own room: a fixed 2 GB on every device (owner, 2026-11-19).
const solaceAllowance = 2048 * 1024 * 1024;
const storeCeiling = 100 * 1024 * 1024;
const dataWarnFraction = 0.8;

enum SpaceState { fine, nearlyFull, full }

/// How full Solace's own room is: its store and its pictures, never the device's space.
SpaceState spaceState(int storeBytes, int pictureBytes) {
  final used = storeBytes + pictureBytes;
  if (used >= solaceAllowance || storeBytes >= storeCeiling) return SpaceState.full;
  if (used >= solaceAllowance * dataWarnFraction || storeBytes >= storeCeiling * dataWarnFraction) {
    return SpaceState.nearlyFull;
  }
  return SpaceState.fine;
}

/// Whether a picture may be added now (not when Solace's own room is full).
bool mayAddPicture(int storeBytes, int pictureBytes) => spaceState(storeBytes, pictureBytes) != SpaceState.full;

/// "4.2 MB" style.
String megabytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

/// The size the store will have once [d] is saved, with every picture kept apart as its own file (measured off the
/// interface thread). An import is refused when this reaches [storeCeiling] (verification round 3, R3-6).
Future<int> storeBytesOf(AppData d) {
  final j = d.toJson();
  j['photos'] = {for (final title in d.photos.keys) title: '$mediaPrefix${'0' * 32}'}; // in the store, a reference
  return Isolate.run(() => utf8.encode(jsonEncode(j)).length + 28); // and AES-GCM's nonce and tag
}

/// What takes the room, by kind, in bytes (measured off the interface thread).
Future<Map<String, int>> spaceByKind(AppData d) {
  final j = d.toJson();
  return Isolate.run(() {
    int size(Object? v) => utf8.encode(jsonEncode(v)).length;
    final conversations = size(j['sessions']);
    final writing = size(j['journal']) + size(j['emotions']) + size(j['story']);
    final total = size(j);
    // pictures are separate files, counted by the caller from their sizes on disk
    return {'Conversations': conversations, 'Journal and feelings': writing,
        'Everything else': (total - conversations - writing).clamp(0, total)};
  });
}

/// Deletes the conversations from before [cutoff] and returns how many. Moods, scores, plans, the safety plan and
/// safety records stay. Through the same [AppData.deleteSessions] as Choose what to delete (round 6 review, E-02:
/// this path removed the conversations only, so the person's words quoted from them stayed in steps, values and
/// noticed things, and a deleted conversation's note still opened the next session), so the two cannot drift.
int deleteConversationsBefore(AppData d, DateTime cutoff) {
  final before = isoDate(cutoff);
  final old = {for (final s in d.sessions) if (s.date.compareTo(before) < 0) s};
  d.deleteSessions(old);
  return old.length;
}

/// How many conversations [deleteConversationsBefore] would delete.
int conversationsBefore(AppData d, DateTime cutoff) {
  final before = isoDate(cutoff);
  return d.sessions.where((s) => s.date.compareTo(before) < 0).length;
}
