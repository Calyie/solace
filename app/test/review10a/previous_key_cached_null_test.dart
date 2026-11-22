// Review round 10 A, R10A-03 (C-08, Android): one failed unwrap of the waiting previous key is remembered as "no
// previous key", and a key renewal later in that session writes over it.
//
// C-08 fixed this for a locked phone only: EncryptedFileVault._previousKey (store.dart:797-808) forgets its answer on
// KeyStoreLocked, with the comment "never remembered as 'no previous key' (a renewal would then write over it)". Any
// other error is still caught and remembered as null for the life of the vault. With C-08 every read of
// `solace_data_key_v1.previous` on Android is an AndroidKeyStore AES-GCM operation (UnlockKey.kt), and any exception
// there other than the few it names comes back as 'failed' (UnlockKey.kt:61-62): a busy or briefly failing Keystore
// (StrongBox has few operation slots) is such a case. KeyWrapLost is another.
//
// Scenario: a key renewal (Settings) is cut short after the store was sealed again but before every picture was (the
// app is ended, or a picture's read-back fails): `.previous` holds key 1, which still opens those pictures. At the next
// opening the unwrap of `.previous` fails once, transiently. The store opens (it is under key 2), no re-seal is queued,
// the pictures under key 1 show as missing. If the person then renews the key again in that session (perhaps because
// pictures are missing), _rotate sees "no previous key", writes key 2 over `.previous`, and key 1 is gone for good:
// those pictures can never be opened again.
//
// The test asserts the SAFE behaviour (the picture still opens at the end), so it fails on 2f3ce71.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

import '../unlocked_only_key_test.dart' show FakeAndroidStorage, FakeUnlockKey;

const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const unlockChannel = MethodChannel('app.personal.solace/unlock_key');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// UnlockKey.kt, with one transient failure ('failed', what UnlockKey.kt answers for any unexpected Keystore
/// exception while the phone is unlocked) on the [failAt]-th unwrap from now.
class FlakyUnlockKey extends FakeUnlockKey {
  int? failAt;
  int _seen = 0;
  @override
  Future<Object?> handle(MethodCall call) {
    if (call.method == 'unwrap' && failAt != null && ++_seen == failAt) {
      failAt = null;
      throw PlatformException(code: 'failed');
    }
    return super.handle(call);
  }

  void failOnUnwrap(int n) {
    failAt = n;
    _seen = 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FlakyUnlockKey unlock;
  late FakeAndroidStorage storage;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('r10a_previous');
    unlock = FlakyUnlockKey();
    storage = FakeAndroidStorage();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(unlockChannel, unlock.handle);
    messenger.setMockMethodCallHandler(secureStorage, storage.handle);
  });
  tearDown(() {
    EncryptedFileVault.debugBeforeReadBack = null;
    messenger.setMockMethodCallHandler(unlockChannel, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  EncryptedFileVault vault() => EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('android'), folder: () async => dir);
  final picture = Uint8List.fromList(List.generate(4000, (i) => i % 251));

  /// A renewal cut short after the store, before the picture: `.previous` (key 1) still needed for the picture.
  Future<String> renewalCutShort() async {
    final first = vault();
    await first.save(AppData()..lastNote = 'mine');
    final id = await first.putMedia(picture);
    EncryptedFileVault.debugBeforeReadBack = (f) async {
      if (f.path.endsWith('.bin.part')) throw const FileSystemException('the app was ended here');
    };
    await expectLater(first.rotateKey(), throwsA(isA<FileSystemException>()));
    EncryptedFileVault.debugBeforeReadBack = null;
    expect(storage.values.containsKey('${EncryptedFileVault.keyName}.previous'), isTrue, reason: 'precondition');
    return id;
  }

  test('R10A-03: a transient failure reading the previous key never lets a renewal write over it', () async {
    final id = await renewalCutShort();
    unlock.failOnUnwrap(2); // the next opening: unwrap 1 is the data key, unwrap 2 the previous key
    final next = vault();
    expect((await next.load()).lastNote, 'mine', reason: 'the store opens: it was already sealed under key 2');
    // Fix round (R10A-03): this line was a precondition that the picture shows as missing, because the failed read was
    // remembered as "no previous key". With the fix the failure is not remembered, so the key is asked for again and
    // the picture opens; the line now asserts that safe behaviour instead.
    expect(listEquals(await next.getMedia(id), picture), isTrue,
        reason: 'the failed read was remembered as "no previous key", so the picture under key 1 shows as missing');
    await next.rotateKey(); // the person renews the key again in this session
    final later = vault();
    await later.load();
    expect(listEquals(await later.getMedia(id), picture), isTrue,
        reason: 'key 1 was written over by key 2 under .previous, then deleted: the picture opens with no key kept');
  });

  test('control: without the transient failure the next opening finishes the renewal and the picture opens', () async {
    final id = await renewalCutShort();
    final next = vault();
    await next.load();
    await next.rotateKey();
    final later = vault();
    await later.load();
    expect(listEquals(await later.getMedia(id), picture), isTrue);
  });
}
