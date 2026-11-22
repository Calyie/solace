// Solace Home (docs/HOME_SERVER.md): the default, air-gapped build has no network code path at all, and the Home
// build's pieces are switched on only by its own entry point and --dart-define=SOLACE_HOME=true. test/privacy_test.dart
// runs unchanged beside this file and still passes: lib/ has no network code.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/home_link.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/home_server.dart';
import 'package:solace/ui/settings.dart';

import '../../home/main_home.dart' as home_entry;
import '../app_flow_test.dart' as flow;

/// Every import and export in [f], with either quote.
Iterable<String> _imports(File f) => RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true)
    .allMatches(f.readAsStringSync()).map((m) => m.group(1)!);

List<File> _dart(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('nothing in lib/ reaches the Home code: the default build cannot contain it', () {
    final offenders = <String>[];
    for (final f in _dart('lib')) {
      for (final i in _imports(f)) {
        // relative imports stay inside lib/; nothing names home/, home_server/ or the Home link's implementation
        final escapes = i.startsWith('../') && File('${f.parent.path}/$i').absolute.path
            .replaceAll(RegExp(r'/[^/]+/\.\.'), '').contains('/app/home/');
        if (escapes || i.contains('home_link_impl') || i.contains('home_server/') || i.contains('main_home') ||
            i.startsWith('package:solace_home')) {
          offenders.add('${f.path}: $i');
        }
      }
    }
    expect(offenders, isEmpty);
    // the one entry point of the default build
    expect(_imports(File('lib/main.dart')).where((i) => i.contains('home')), ['core/home_link.dart', 'ui/home.dart']);
  });

  test('the default build has no Home link and does not say it is the Home build', () {
    expect(homeBuild, isFalse, reason: 'tests, like the default build, are made without SOLACE_HOME');
    expect(homeLink, isNull);
    expect(homeOffered, isFalse);
  });

  test('the Home entry point compiles, and refuses to start without SOLACE_HOME=true (so its wording and platform '
      'pieces always match)', () async {
    await expectLater(home_entry.main(), throwsA(isA<StateError>()));
    expect(homeLink, isNull, reason: 'refused before the link was set');
  });

  test('the only network code is in home/, and it is reached only from the Home entry point', () {
    const network = r'HttpClient|SecureSocket|Socket\.|HttpOverrides|connectionFactory|ServerSocket|RawSocket';
    final withNetwork = [
      for (final f in [..._dart('lib'), ..._dart('home')])
        if (RegExp(network).hasMatch([for (final l in f.readAsLinesSync()) if (!l.trimLeft().startsWith('//')) l]
            .join('\n'))) f.path.replaceAll(r'\', '/'),
    ]..sort();
    // the default guard (it refuses) and the Home link (it allows only the paired server)
    expect(withNetwork, ['home/home_link_impl.dart', 'lib/core/network_guard.dart']);
    final entry = File('home/main_home.dart').readAsStringSync();
    expect(entry, contains('if (!homeBuild) throw StateError('));
    expect(entry, contains('homeLink = GatewayHomeLink();'));
    expect(File('lib/core/home_link.dart').readAsStringSync(), contains("bool.fromEnvironment('SOLACE_HOME')"));
  });

  test('Android: only a Home release build gets the internet permission', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('android.permission.INTERNET')));
    expect(File('android/app/src/home/AndroidManifest.xml').readAsStringSync(),
        contains('<uses-permission android:name="android.permission.INTERNET"/>'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    // Flutter passes each define base64-encoded in the dart-defines property; only SOLACE_HOME=true adds the overlay
    expect(gradle, contains('providers.gradleProperty("dart-defines")'));
    expect(gradle, contains('== "SOLACE_HOME=true"'));
    expect(gradle, contains('if (solaceHome) {\n        sourceSets.getByName("release").manifest.srcFile("src/home/AndroidManifest.xml")'));
    expect(RegExp('src/home/AndroidManifest.xml').allMatches(gradle), hasLength(2), reason: 'a comment and the use');
  });

  test('Mac: the default release entitlements have no network; the Home ones add only network.client', () {
    final release = File('macos/Runner/Release.entitlements').readAsStringSync();
    final home = File('macos/Runner/ReleaseHome.entitlements').readAsStringSync();
    expect(release, isNot(contains('network')));
    expect(home, contains('<key>com.apple.security.network.client</key>\n\t<true/>'));
    expect(home, isNot(contains('network.server')));
    Set<String> keys(String s) => RegExp(r'<key>([^<]+)</key>').allMatches(s).map((m) => m.group(1)!).toSet();
    expect(keys(home).difference(keys(release)), {'com.apple.security.network.client'});
    expect(keys(release).difference(keys(home)), isEmpty, reason: 'the sandbox and everything else as in Release');
    // the project still signs every configuration with the default files (privacy_test checks the same)
    expect(File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync(), isNot(contains('ReleaseHome')));
  });

  test('iPhone: the default Info.plist has no local network text (the Home build script adds it for its build)', () {
    expect(File('ios/Runner/Info.plist').readAsStringSync(), isNot(contains('NSLocalNetworkUsageDescription')));
    expect(File('../tools/home/build_home.sh').readAsStringSync(), contains('Add :NSLocalNetworkUsageDescription'));
  });

  test('Linux: the network block is relaxed only when the build was given SOLACE_HOME=true', () {
    final cmake = File('linux/runner/CMakeLists.txt').readAsStringSync();
    // "U09MQUNFX0hPTUU9dHJ1ZQ==" is base64 for "SOLACE_HOME=true", as Flutter writes each define
    expect(cmake, contains('U09MQUNFX0hPTUU9dHJ1ZQ=='));
    expect(cmake, contains('target_compile_definitions(\${BINARY_NAME} PRIVATE SOLACE_HOME_NET)'));
    final filter = File('linux/runner/net_block.h').readAsStringSync();
    final start = filter.indexOf('#ifndef SOLACE_HOME_NET');
    final branch = filter.substring(start, filter.indexOf('#else', start));
    // the default build's filter: local and netlink sockets only, exactly as before
    expect(branch, contains('BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_UNIX, 2, 0)'));
    expect(branch, contains('BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_NETLINK, 1, 0)'));
    expect(branch, isNot(contains('AF_INET')));
  });

  testWidgets('Settings offers no Home server in the default build', (tester) async {
    final state = flow.makeState();
    await flow.pumpApp(tester, state);
    Navigator.of(tester.element(find.byType(Scaffold).first))
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('settings_about')), 400,
        scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const Key('open_home_server')), findsNothing);
    expect(find.text('Home server'), findsNothing);
  });

  test('the pairing is kept in the encrypted settings, never in a transfer file, and an import keeps this device\'s',
      () async {
    const mine = HomePairing(host: '100.64.0.2', port: 8443, certSha256: 'cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34cd34',
        token: 'MineMineMineMineMineMineMineMineMineMine123', deviceId: 'mine12345678', date: '2026-11-19');
    const theirs = HomePairing(host: '192.168.1.9', port: 8443, certSha256: 'ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56ef56',
        token: 'TheirsTheirsTheirsTheirsTheirsTheirsTheirs1', deviceId: 'theirs123456', date: '2026-11-19');
    final s = Settings()..homeServer = mine;
    expect(Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>).homeServer!.token, mine.token);
    final code = TransferCode.generate(Random(41));
    final other = AppData()..settings.homeServer = theirs;
    final sealed = await TransferFile.seal(other, code, random: Random(42));
    final opened = await TransferFile.open(sealed, code);
    expect(opened.settings.homeServer, isNull, reason: 'not in the file');
    final here = AppData()..settings.homeServer = mine;
    expect(importInto(here, opened).settings.homeServer!.token, mine.token);
  });

  test('a pairing is read back only in the shape this version writes', () {
    const good = HomePairing(host: '192.168.1.20', port: 8443, certSha256: 'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12',
        token: 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcd', deviceId: 'dev123456789', date: '2026-11-19');
    final back = HomePairing.fromJson(good.toJson())!;
    expect(back.toJson(), good.toJson());
    for (final bad in [
      {...good.toJson(), 'port': 0},
      {...good.toJson(), 'cert_sha256': 'xyz'},
      {...good.toJson(), 'token': 'short'},
      {...good.toJson(), 'host': 'evil host/path'},
      'not a map',
    ]) {
      expect(HomePairing.fromJson(bad), isNull, reason: '$bad');
    }
  });
}
