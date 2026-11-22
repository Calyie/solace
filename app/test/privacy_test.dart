// Nothing leaves the device: release builds have no network permission, and the app's code uses no network library.
// (Plugins can add permissions when Android merges manifests; the merged manifest is checked again after a build.)
// Owner, 2026-11-13: air-gapped with no network access at all, and nothing shared with the base model's maker. Two
// libraries carry an optional network path the app must never call: llamadart (model downloads: ModelSource.url,
// .huggingFace, .parse of a web address, its download manager) and audioplayers (playing from a web link). iOS has no
// network switch, so these tests are its guard; Android and the macOS sandbox block the network as well.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/premium.dart';

const _bootClock = 'lib/core/boot_clock.dart';

void main() {
  test('the Android release manifest has no internet permission', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('android.permission.INTERNET')));
  });

  test('the macOS release build has no network entitlement', () {
    expect(File('macos/Runner/Release.entitlements').readAsStringSync(), isNot(contains('network')));
  });

  test('no app code uses a network library', () {
    const network = r"HttpClient|package:http/|dart:html|WebSocket|Socket\.connect|Socket\.startConnect|package:dio|"
        r"package:web_socket|RawDatagramSocket|http://|https://|ServerSocket|HttpServer|InternetAddress\.lookup|"
        r"RawSocket|SecureSocket|NetworkInterface|package:url_launcher|launchUrl|"
        r"ModelSource\.(url|huggingFace|parse)|ModelDownload|RemoteModelUrl|downloadOnce|UrlSource|setSourceUrl|playUrl|"
        r"Process\.start|Process\.runSync";
    // A native library reached through dart:ffi could open a socket without any network library, so native lookups
    // are banned too (audit 216 added @Native, lookupFunction and providesSymbol beside DynamicLibrary). The one
    // exception is the boot clock (lib/core/boot_clock.dart, audit 216, G7-06), whose every lookup is checked by the
    // next test.
    // Round 10 review B (R10B-04): dart:ffi and package:ffi themselves, with either quote, and Native<...> with or
    // without a prefix (`@ffi.Native<...>(symbol: ...)`, the form ffigen writes).
    final banned = RegExp('$network|DynamicLibrary|@Native\\b|lookupFunction|providesSymbol|\\.lookup<|dart:ffi|'
        'package:ffi|\\bNative\\s*<|\\.Native\\b|fromAddress|asFunction');
    final bannedInBootClock = RegExp(network);
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      // the network guard names these types only to refuse them (checked in the next test, and by network_guard_test)
      // (that exact file only, round 10 review B, R10B-04: not any path that merely ends with its name)
      if (f.path.replaceAll(r'\', '/') == 'lib/core/network_guard.dart') continue;
      final rule = f.path.replaceAll(r'\', '/') == _bootClock ? bannedInBootClock : banned;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // the one dart:ffi import allowed outside the boot clock: Abi alone (the processor type, llama_model.dart),
        // which cannot reach a native function
        if (lines[i].trim() == "import 'dart:ffi' show Abi;") continue;
        if (!lines[i].trimLeft().startsWith('//') && rule.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the in-app network guards only refuse, and main() installs them before the first screen (AIR-3)', () {
    final guard = File('lib/core/network_guard.dart').readAsStringSync();
    // nothing to reach a network with: dart:io and the error log only, no web client handed out
    // imports and exports read with either quote (round 10 review B, R10B-04)
    expect(RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(guard)
        .map((m) => m.group(1)).toSet(), {'dart:io', 'error_log.dart'});
    final guardCode = [for (final l in guard.split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
    expect(guardCode, isNot(matches(RegExp(r'dart:ffi|package:ffi|DynamicLibrary|Native|lookupFunction|'
        r'providesSymbol|fromAddress|asFunction|RawSocket|SecureSocket|https?://'))));
    expect(guard, isNot(contains('super.createHttpClient')));
    expect(guard, contains('HttpClient createHttpClient(SecurityContext? context) => _refuse('));
    // the real socket calls are reached only for a Unix-domain address (a file on the device)
    for (final call in ['super.socketConnect(', 'super.socketStartConnect(', 'super.serverSocketBind(']) {
      final lines = guard.split('\n').where((l) => l.contains(call)).toList();
      expect(lines, hasLength(1), reason: call);
      expect(lines.single, contains('_local('), reason: call);
    }
    // main() installs them before anything else runs or is shown
    final main = File('lib/main.dart').readAsStringSync();
    final body = main.substring(main.indexOf('Future<void> main() async {'));
    expect(body.indexOf('installNetworkGuards();'), greaterThan(0));
    expect(body.indexOf('installNetworkGuards();'), lessThan(body.indexOf('runApp(')));
    expect(body.indexOf('installNetworkGuards();'), lessThan(body.indexOf('rootBundle')));
  });

  test('Linux release builds install the seccomp network block first thing in main() (AIR-3)', () {
    final main = File('linux/runner/main.cc').readAsStringSync();
    expect(main, contains('#include "net_block.h"'));
    final start = main.indexOf('int main(');
    final block = main.indexOf('solace_block_network()'), env = main.indexOf('setenv("SOLACE_NET_BLOCK"');
    expect(block, greaterThan(start));
    expect(env, greaterThan(block));
    expect(block, lessThan(main.indexOf('my_application_new()')), reason: 'before GTK and any thread');
    expect(block, lessThan(main.indexOf('prctl(PR_SET_DUMPABLE')), reason: 'the very first thing');
    // release builds only (debug and profile builds need the VM service's loopback socket)
    expect(File('linux/runner/CMakeLists.txt').readAsStringSync(),
        contains(r'"$<$<CONFIG:Release>:SOLACE_RELEASE_NET_BLOCK>"'));
    final filter = File('linux/runner/net_block.h').readAsStringSync();
    for (final part in ['PR_SET_NO_NEW_PRIVS', 'SECCOMP_SET_MODE_FILTER', 'SECCOMP_FILTER_FLAG_TSYNC',
        'AUDIT_ARCH_X86_64', 'AUDIT_ARCH_AARCH64', '__NR_io_uring_setup', '__NR_socket', 'AF_UNIX', 'AF_NETLINK',
        'EACCES', 'ENOSYS']) {
      expect(filter, contains(part), reason: part);
    }
    expect(filter, contains('return false;  // an architecture'), reason: 'nothing installed on an unknown one');
  });

  test('the iPhone and the Mac fail every web request at launch (AIR-3)', () {
    for (final f in ['ios/Runner/AppDelegate.swift', 'macos/Runner/AppDelegate.swift']) {
      final d = File(f).readAsStringSync();
      expect(d, contains('URLProtocol.registerClass(NoNetworkProtocol.self)'), reason: f);
      expect(d, contains('NoNetworkProtocol.install()'), reason: '$f: installed at launch');
      // a session with its own configuration never asks the registered classes (round 10 device check), so the guard
      // is put first in every configuration the two standard class methods hand out
      for (final part in ['"defaultSessionConfiguration", "ephemeralSessionConfiguration"',
          'configuration.protocolClasses = [NoNetworkProtocol.self] + others', 'method_setImplementation(method,']) {
        expect(d, contains(part), reason: '$f: $part');
      }
      expect(d, contains('class NoNetworkProtocol: URLProtocol'), reason: f);
      expect(d, contains('["http", "https", "ws", "wss", "ftp"]'), reason: f);
      expect(d, contains('URLError(.notConnectedToInternet)'), reason: f);
    }
  });

  test('the boot clock looks up only clock and memory functions through dart:ffi (audit 216, G7-06)', () {
    // every quoted text in its code: the libc names it may open and the symbols it may look up, nothing else (a new
    // symbol, such as socket or connect, would be a new quoted text and fail here)
    const allowed = {'dart:ffi', 'dart:io', 'libc.so', 'libc.so.6', 'clock_gettime', 'malloc', 'free',
        'mach_continuous_time', 'mach_timebase_info', 'no libc'};
    final code = [for (final l in File(_bootClock).readAsLinesSync()) if (!l.trimLeft().startsWith('//')) l].join('\n');
    expect(code, isNot(contains('"')), reason: 'single quotes only, so the check below sees every text');
    expect(code, isNot(contains(r'$')), reason: 'no text built from parts');
    final texts = RegExp("'([^']*)'").allMatches(code).map((m) => m.group(1)!).toSet();
    expect(texts.difference(allowed), isEmpty);
    expect(texts, containsAll(['clock_gettime', 'mach_continuous_time']), reason: 'the file was read');
    // Round 10 review B (R10B-04): a name built from the allowed texts ('mach_continuous_time'[14] + ...) or from
    // character codes would pass the check above, so every lookup, symbol check and library open takes only allowed
    // literals (and Platform tests between them), and the other ways to reach a function are banned here too.
    expect(code, isNot(matches(RegExp(r'fromCharCode|codeUnits|runes|fromAddress|asFunction|\bNative\b|'
        r'String\.|\.substring|\.split|\.join|replaceAll'))));
    final call = RegExp(r'\b(lookupFunction|lookup|providesSymbol|DynamicLibrary\.open)\b\s*');
    var calls = 0;
    for (final m in call.allMatches(code)) {
      var i = m.end;
      if (i < code.length && code[i] == '<') { // skip the type arguments, balanced
        var depth = 0;
        do {
          if (code[i] == '<') depth++;
          if (code[i] == '>') depth--;
          i++;
        } while (i < code.length && depth > 0);
        while (i < code.length && code[i].trim().isEmpty) {
          i++;
        }
      }
      expect(i < code.length && code[i] == '(', isTrue, reason: 'a call: ${m.group(1)} at offset ${m.start}');
      var depth = 0, j = i;
      do {
        if (code[j] == '(') depth++;
        if (code[j] == ')') depth--;
        j++;
      } while (j < code.length && depth > 0);
      var args = code.substring(i + 1, j - 1);
      for (final a in allowed) {
        args = args.replaceAll("'$a'", ' ');
      }
      args = args.replaceAll(RegExp(r'Platform\.is\w+|isLeaf:\s*(true|false)|[?:,\s]'), '');
      expect(args, isEmpty, reason: '${m.group(1)} at offset ${m.start} takes only allowed literals');
      calls++;
    }
    expect(calls, greaterThanOrEqualTo(6), reason: 'the lookups were found');
  });

  test('no network, Google, analytics or crash-report package ships in the app, beyond the two known optional paths', () {
    // Every package that ships (dart pub deps --no-dev: test-only tools such as integration_test's sync_http are left
    // out, 2026-11-13); http and http_parser come only with llamadart and audioplayers (their optional download and
    // web-link features, banned above). A new match here means a new shipped package that could reach a network.
    // the Dart of the Flutter running this test (round 9 review: 'dart' alone failed whenever it was not on PATH)
    final deps = Process.runSync(_dart(), ['pub', 'deps', '--no-dev', '--style=list']);
    expect(deps.exitCode, 0, reason: '${deps.stderr}');
    final names = RegExp(r'^- ([a-z0-9_]+) ', multiLine: true).allMatches(deps.stdout as String).map((m) => m.group(1)!).toSet();
    expect(names, contains('llamadart'), reason: 'the package list was read');
    final risky = RegExp(r'http|firebase|google|gms|analytics|crash|sentry|bugsnag|datadog|socket|grpc|connectivity|'
        r'url_launcher|webview|cloud|_fonts|telemetry|^dio|amplify|supabase|appwrite|mixpanel|segment|posthog');
    expect(names.where(risky.hasMatch).toSet(), {'http', 'http_parser'});
  });

  test('the only program the app ever starts is df, for the free space on Linux (verification round 2, AIR-3)', () {
    final uses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Process.run(')) uses.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(uses, hasLength(1));
    expect(uses.single, allOf(contains('lib/core/media.dart'), contains("Process.run('df'")));
  });

  test('the platform code of the app itself opens no network connection (verification round 2, AIR-3)', () {
    // URLSessionConfiguration is allowed: the AIR-3 guard names it only to put itself first in every configuration
    // (pinned by the next test); a session or connection made from it is still caught (URLSession(, URLSession.shared)
    final banned = RegExp(r'URLSession(?!Configuration)|NSURLConnection|HttpURLConnection|OkHttp|java\.net\.|Socket\(|'
        r'\bsocket\(|\bconnect\(|getaddrinfo|libcurl|soup_session|g_socket|CFNetwork|Network\.framework|NWConnection');
    final files = [
      ...Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>(),
      ...Directory('ios/Runner').listSync().whereType<File>().where((f) => f.path.endsWith('.swift')),
      ...Directory('macos/Runner').listSync().whereType<File>().where((f) => f.path.endsWith('.swift')),
      ...Directory('linux/runner').listSync().whereType<File>().where((f) => RegExp(r'\.(cc|h)$').hasMatch(f.path)),
    ];
    expect(files.length, greaterThanOrEqualTo(5), reason: 'the runners were found');
    // comments name what the guard blocks, so only code is read
    // whole comment lines only (round 10 review B, R10B-05: a `//` inside a string must not hide the rest of a line)
    String code(File f) => [for (final l in f.readAsLinesSync()) if (!l.trimLeft().startsWith('//')) l].join('\n');
    final offenders = [for (final f in files) if (banned.hasMatch(code(f))) f.path];
    expect(offenders, isEmpty);
  });

  test('the macOS build is sandboxed in both configurations, and the release build has no network entitlement '
      '(security review AIR-3)', () {
    // every build configuration (Debug, Profile, Release) signs with one of these two files
    final used = RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/(\w+)\.entitlements;')
        .allMatches(File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync()).map((m) => m.group(1)).toList();
    expect(used.toSet(), {'DebugProfile', 'Release'});
    expect(used, hasLength(3), reason: 'Debug, Profile and Release');
    for (final f in ['macos/Runner/Release.entitlements', 'macos/Runner/DebugProfile.entitlements']) {
      final e = File(f).readAsStringSync();
      expect(e, contains('com.apple.security.app-sandbox'), reason: f);
      // set to true, not only named (verification round 2)
      expect(RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<true/>').hasMatch(e), isTrue, reason: f);
      // the debug profile (Debug and Profile builds) keeps network.server for Flutter's debugging connection, and
      // never network.client; the release build has neither
      expect(e.contains('com.apple.security.network.client'), isFalse, reason: f);
      if (f.contains('Release')) expect(e.contains('com.apple.security.network.server'), isFalse, reason: f);
    }
  });

  test('Android backs nothing up and offers no text to other apps (security review F-06, F-10)', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m, contains('android:allowBackup="false"'));
    expect(m, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(RegExp(r'<action android:name="android.intent.action.PROCESS_TEXT"').hasMatch(m), isFalse);
    // OW-M8-2, round 3 R3-8: Flutter reads the deep-link switch from the activity's own meta-data, not the application's
    final activity = RegExp(r'<activity\s[^>]*android:name="\.MainActivity"[\s\S]*?</activity>').firstMatch(m)!.group(0)!;
    expect(activity, contains('<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />'));
    final main = Directory('android').listSync(recursive: true).whereType<File>()
        .firstWhere((f) => f.path.endsWith('MainActivity.kt')).readAsStringSync();
    // owner, 2026-11-19: screenshots and screen recording are never blocked; "Hide in the app switcher" hides only the
    // recent-apps preview (Android 13 and later), which leaves screenshots alone
    final code = [for (final l in main.split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
    expect(code, isNot(contains('FLAG_SECURE')));
    expect(code, contains('setRecentsScreenshotEnabled(!hidden)'));
    // round 8, OW-M8-2: touches refused for the whole gesture while another app draws over Solace, and the intent's
    // link removed with its extras (the native file cannot be built here; this keeps the code from being dropped)
    expect(main, contains('override fun dispatchTouchEvent'));
    expect(main, contains('MotionEvent.FLAG_WINDOW_IS_OBSCURED'));
    expect(main, contains('MotionEvent.ACTION_CANCEL'));
    expect(main, contains('data = null'));
  });

  test('every text field turns keyboard learning and autofill off and keeps the system\'s own text menu (security '
      'review F-10, AIR-2; round 9 review, 9A-05; owner, 2026-11-19)', () {
    final offenders = <String>[];
    var boxes = 0;
    for (final (file, src, start, args) in _calls(RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\('))) {
      boxes++;
      // autofillHints null is the only value that turns autofill off (Flutter's default is an empty list, which
      // reports the box, its words and every change to the platform's autofill service)
      // the system's own menu, with Copy, Cut, Paste and Select all (owner, 2026-11-19: the private menu is gone)
      if (!args.contains('enableIMEPersonalizedLearning: false') || args.contains('contextMenuBuilder:') ||
          !RegExp(r'autofillHints: (null|PrivateKeyboard\.autofillHints)\b').hasMatch(args)) {
        offenders.add('$file:${_line(src, start)}');
      }
    }
    expect(boxes, greaterThanOrEqualTo(28), reason: 'the boxes were found');
    expect(PrivateKeyboard.autofillHints, isNull);
    expect(offenders, isEmpty);
    // and nothing else in lib takes text from the keyboard without these checks
    final other = RegExp(r'\b(EditableText|SearchBar|SearchAnchor|Autocomplete|RawAutocomplete|DropdownMenu)\b\s*[<(]');
    final unchecked = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trimLeft().startsWith('//') && other.hasMatch(lines[i])) unchecked.add('${f.path}:${i + 1}');
      }
    }
    expect(unchecked, isEmpty);
  });

  testWidgets('a box with PrivateKeyboard.autofillHints is never offered to autofill (round 9 review, 9A-05)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(home: Material(child: TextField(autofillHints: PrivateKeyboard.autofillHints,
          enableIMEPersonalizedLearning: false, obscureText: true))));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('every text box keeps what is typed out of the iPhone keyboard\'s learning (round 5 review, C-05)', () {
    // enableIMEPersonalizedLearning (above) is an Android flag; the iPhone's keyboard learns from any box with
    // autocorrection on. Every box takes autocorrection, suggestions and spell checking from PrivateKeyboard (off on
    // the iPhone), or turns them off on every device. A box with obscureText is a secure entry on the iPhone, which
    // the keyboard never learns from (the passphrase boxes).
    final offenders = <String>[];
    for (final (file, src, start, args) in _calls(RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\('))) {
      if (args.contains('obscureText: true')) continue;
      final ok = RegExp(r'autocorrect: (false|PrivateKeyboard\.autocorrect)\b').hasMatch(args) &&
          RegExp(r'enableSuggestions: (false|PrivateKeyboard\.suggestions)\b').hasMatch(args) &&
          args.contains('spellCheckConfiguration: PrivateKeyboard.spellCheck');
      if (!ok) offenders.add('$file:${_line(src, start)}');
    }
    expect(offenders, isEmpty);
  });

  testWidgets('on the iPhone a text box asks the keyboard for no autocorrection, suggestions or spell checking; '
      'Android keeps autocorrection (round 5 review, C-05)', (tester) async {
    Future<EditableText> box(TargetPlatform p) async {
      debugDefaultTargetPlatformOverride = p;
      await tester.pumpWidget(MaterialApp(key: ValueKey(p), home: Material(child: TextField(
          enableIMEPersonalizedLearning: false,
          autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions,
          spellCheckConfiguration: PrivateKeyboard.spellCheck))));
      return tester.widget<EditableText>(find.byType(EditableText));
    }
    try {
      final iPhone = await box(TargetPlatform.iOS);
      expect(iPhone.autocorrect, isFalse); // UITextAutocorrectionTypeNo and UITextSpellCheckingTypeNo
      expect(iPhone.enableSuggestions, isFalse);
      expect(iPhone.spellCheckConfiguration?.spellCheckEnabled ?? false, isFalse);
      final android = await box(TargetPlatform.android);
      expect(android.autocorrect, isTrue);
      expect(android.enableSuggestions, isTrue);
      expect(android.enableIMEPersonalizedLearning, isFalse); // Android's incognito flag stops the learning
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('text the person reads can be selected and copied with the system\'s own menu (owner, 2026-11-19)', () {
    // "remove this option you have that prevents screenshotting on solace or right-clicking and copying text from
    // solace as that is tiring and frustrating": no private menu anywhere, and every reading screen is laid out in a
    // Readable, which is a SelectionArea with the standard menu (ui/premium.dart)
    final offenders = <String>[];
    for (final (file, src, start, args) in _calls(RegExp(r'\b(SelectableText(\.rich)?|SelectionArea)\('))) {
      if (args.contains('contextMenuBuilder:')) offenders.add('$file:${_line(src, start)}');
    }
    expect(offenders, isEmpty);
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(matches(RegExp('privateContextMenu|privateSelectionMenu|ClipboardGuard'))),
          reason: f.path);
    }
    final premium = File('lib/ui/premium.dart').readAsStringSync();
    expect(premium, contains('selectable ? SelectionArea(child: box) : box'));
  });

  test('every text box has a length limit, so a huge paste is cut and never freezes the app (owner, 2026-11-14)', () {
    final offenders = <String>[];
    for (final (file, src, start, args) in _calls(RegExp(r'\b(TextField|TextFormField|CupertinoTextField)\('))) {
      if (_limitsByOwner.contains(file.split('/').last)) continue;
      if (!args.contains('maxLength:') && !args.contains('LengthLimitingTextInputFormatter')) {
        offenders.add('$file:${_line(src, start)}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the iPhone app keeps its data out of backups and allows only the system keyboard (security review F-03, F-10)', () {
    final d = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(d, contains('isExcludedFromBackup = true'));
    expect(d, contains('extensionPointIdentifier != .keyboard'));
  });

  // The native code cannot be built here (no Mac); these keep it from being dropped.
  test('the iPhone covers its windows natively as soon as the app is not in front (round 9 review, 9A-07)', () {
    final scene = File('ios/Runner/SceneDelegate.swift').readAsStringSync();
    for (final s in ['UIScene.willDeactivateNotification', 'UIScene.didActivateNotification', 'window.addSubview(cover)',
        'view.removeFromSuperview()', 'queue: nil']) {
      expect(scene, contains(s), reason: s);
    }
    expect(File('ios/Runner/AppDelegate.swift').readAsStringSync(), contains('SwitcherCover.start()'));
  });

  test('the Mac menu bar has no Services menu, and no Start Dictation or Emoji & Symbols (round 9 review, 9A-06)', () {
    expect(File('macos/Runner/Base.lproj/MainMenu.xib').readAsStringSync(), isNot(contains('systemMenu="services"')));
    final app = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final early = app.substring(app.indexOf('applicationWillFinishLaunching'));
    for (final key in ['NSDisabledDictationMenuItem', 'NSDisabledCharacterPaletteMenuItem']) {
      expect(early, contains('set(true, forKey: "$key")'), reason: key);
    }
    expect(File('lib/ui/desktop.dart').readAsStringSync(), isNot(contains('PlatformProvidedMenuItemType.servicesSubmenu')));
  });

  // Owner, 2026-11-15: "The app should not require Face ID in anyway for anything especially authentication". The app
  // lock and every "confirm it is you" use only Solace's own six-digit passcode (ui/app_lock.dart), on every device.
  test('Solace never uses Face ID, Touch ID, a fingerprint or the device\'s own unlock (owner, 2026-11-15)', () {
    // no package for it is asked for or ships
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('local_auth')));
    expect(File('pubspec.lock').readAsStringSync(), isNot(contains('local_auth')));
    // no word for it in the app's code or on its screens; "fingerprint" is allowed only where it names the deep work
    // key's salted Argon2id hash (core/full_mode_key.dart FullModeKey.fingerprint), never anything about a finger
    final banned = RegExp(r'\bface ?id\b|\btouch ?id\b|biometric|local_auth|LocalAuthentication|Icons\.fingerprint|'
        r'device passcode', caseSensitive: false);
    final hashSense = RegExp(r'Argon2id|salted|FullModeKey|fingerprintOf|32-byte');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final finger = l.toLowerCase().contains('fingerprint') && !f.path.endsWith('full_mode_key.dart') &&
            !hashSense.hasMatch(l);
        if (banned.hasMatch(l) || finger) offenders.add('${f.path}:${i + 1}: ${l.trim()}');
      }
    }
    expect(offenders, isEmpty);
    // no platform asks for it, and no native code calls it
    for (final plist in ['ios/Runner/Info.plist', 'macos/Runner/Info.plist']) {
      expect(File(plist).readAsStringSync(), isNot(contains('NSFaceIDUsageDescription')), reason: plist);
    }
    for (final m in Directory('android/app/src').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('AndroidManifest.xml'))) {
      expect(m.readAsStringSync(), isNot(matches(RegExp('USE_BIOMETRIC|USE_FINGERPRINT'))), reason: m.path);
    }
    // (the app's own native code and the plugin lists Flutter generates; never the ephemeral folders of plugin links)
    final native = RegExp(r'LocalAuthentication|LAContext|BiometricPrompt|BiometricManager|FingerprintManager|local_auth');
    final sources = [
      for (final dir in ['ios/Runner', 'macos/Runner', 'android/app/src/main/kotlin', 'linux/runner', 'windows/runner'])
        ...Directory(dir).listSync(recursive: true, followLinks: false).whereType<File>()
            .where((f) => RegExp(r'\.(swift|m|h|kt|java|cc|cpp)$').hasMatch(f.path)),
      for (final f in ['macos/Flutter/GeneratedPluginRegistrant.swift', 'linux/flutter/generated_plugins.cmake',
          'linux/flutter/generated_plugin_registrant.cc', 'windows/flutter/generated_plugins.cmake',
          'windows/flutter/generated_plugin_registrant.cc'])
        File(f),
    ];
    for (final f in sources) {
      expect(native.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}

// Screens whose owner is setting these themselves in a parallel change (2026-11-14); listed here so the checks above
// cover every other file now, and these once that change is merged (then remove them from the list).
const _limitsByOwner = <String>{};

int _line(String src, int at) => '\n'.allMatches(src.substring(0, at)).length + 1;

/// The Dart of the Flutter SDK running these tests: FLUTTER_ROOT (which flutter test sets), else found from the test
/// runner's own path (`<flutter>/bin/cache/artifacts/engine/<platform>/flutter_tester`), else whatever is on PATH.
String _dart() {
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  final roots = [
    if (Platform.environment['FLUTTER_ROOT'] case final root? when root.isNotEmpty) '$root/bin/cache',
    for (var d = File(Platform.resolvedExecutable).parent; d.parent.path != d.path; d = d.parent)
      if (d.uri.pathSegments.where((p) => p.isNotEmpty).last == 'cache') d.path,
  ];
  for (final cache in roots) {
    final dart = File('$cache/dart-sdk/bin/$exe');
    if (dart.existsSync()) return dart.path;
  }
  return exe;
}

/// Every call of [pattern] in lib/: the file, its source, where the call starts, and its arguments up to the matching
/// bracket (string literals skipped, so a bracket inside a string never ends the call early).
Iterable<(String, String, int, String)> _calls(RegExp pattern) sync* {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    for (final m in pattern.allMatches(src)) {
      var depth = 0, i = m.end - 1;
      for (; i < src.length; i++) {
        final c = src[i];
        if (c == "'" || c == '"') {
          final triple = src.startsWith(c * 3, i);
          final close = triple ? c * 3 : c;
          i += close.length;
          while (i < src.length && !src.startsWith(close, i)) {
            if (src[i] == '\\' && (i == 0 || src[i - 1] != 'r')) i++;
            i++;
          }
          i += close.length - 1;
        } else if (c == '(') {
          depth++;
        } else if (c == ')' && --depth == 0) {
          break;
        }
      }
      yield (f.path, src, m.start, src.substring(m.end, i.clamp(m.end, src.length)));
    }
  }
}
