// AIR-3 (owner, 2026-11-16): the in-app network guards (core/network_guard.dart), the only kind the iPhone allows and
// an addition to the operating system's blocks elsewhere. Once installed, making a web client throws, and
// Socket.connect, Socket.startConnect and ServerSocket.bind fail for every internet address and host name, each with
// NetworkRefused, recorded once per kind in ErrorLog (its type only). A Unix-domain socket (a file on this device) still
// works, and so does everything else dart:io does (files). Nothing here reaches a network: a refused call makes no
// socket, and the local checks use a socket file in a temporary folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/error_log.dart';
import 'package:solace/core/network_guard.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('guard');
    ErrorLog.seen.clear();
    installNetworkGuards();
  });
  tearDown(() {
    HttpOverrides.global = null;
    IOOverrides.global = null;
    dir.deleteSync(recursive: true);
  });

  test('a web client cannot be made', () {
    expect(() => HttpClient(), throwsA(isA<NetworkRefused>()));
    expect(() => HttpClient(context: SecurityContext.defaultContext), throwsA(isA<NetworkRefused>()));
    expect(ErrorLog.seen, ['NetworkRefused'], reason: 'two tries, one record, by its type only');
  });

  test('Socket.connect is refused for an internet address, a host name and IPv6', () async {
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, 9), throwsA(isA<NetworkRefused>()));
    await expectLater(Socket.connect('127.0.0.1', 9), throwsA(isA<NetworkRefused>()));
    await expectLater(Socket.connect('example.org', 443), throwsA(isA<NetworkRefused>()));
    await expectLater(Socket.connect(InternetAddress.loopbackIPv6, 9, timeout: const Duration(seconds: 1)),
        throwsA(isA<NetworkRefused>()));
  });

  test('Socket.startConnect is refused', () async {
    await expectLater(Socket.startConnect('127.0.0.1', 9), throwsA(isA<NetworkRefused>()));
  });

  test('ServerSocket.bind is refused, on loopback and on every address', () async {
    await expectLater(ServerSocket.bind(InternetAddress.loopbackIPv4, 0), throwsA(isA<NetworkRefused>()));
    await expectLater(ServerSocket.bind(InternetAddress.anyIPv6, 0), throwsA(isA<NetworkRefused>()));
    await expectLater(ServerSocket.bind('localhost', 0), throwsA(isA<NetworkRefused>()));
  });

  test('each kind of refusal is recorded once a run, never again', () async {
    for (var i = 0; i < 3; i++) {
      expect(() => HttpClient(), throwsA(isA<NetworkRefused>()));
      await expectLater(Socket.connect('127.0.0.1', 9), throwsA(isA<NetworkRefused>()));
      await expectLater(ServerSocket.bind('127.0.0.1', 0), throwsA(isA<NetworkRefused>()));
    }
    // (the tests above already recorded web, connect and listen once each in this run)
    expect(ErrorLog.seen, isEmpty, reason: 'nothing more is recorded however often it is tried');
    expect('${const NetworkRefused()}', 'Solace never connects to the internet, so this was stopped.');
  });

  test('a local (Unix-domain) socket and files still work', () async {
    final path = InternetAddress('${dir.path}/s', type: InternetAddressType.unix);
    final server = await ServerSocket.bind(path, 0);
    final accepted = server.first;
    final client = await Socket.connect(path, 0);
    final other = await accepted;
    client.add([1, 2, 3]);
    await client.flush();
    expect(await other.first, [1, 2, 3]);
    client.destroy();
    other.destroy();
    await server.close();
    final f = File('${dir.path}/a.txt')..writeAsStringSync('kept');
    expect(f.readAsStringSync(), 'kept');
  });

  test('Settings > Private by design says what the operating system itself blocks', () {
    expect(networkBlockNote(os: 'android'), contains('internet permission'));
    expect(networkBlockNote(os: 'macos'), contains('sandbox'));
    expect(networkBlockNote(os: 'linux', environment: {'SOLACE_NET_BLOCK': 'on'}), startsWith('Linux itself'));
    expect(networkBlockNote(os: 'linux', environment: {'SOLACE_NET_BLOCK': 'off'}), contains('not on'));
    expect(networkBlockNote(os: 'linux', environment: {}), contains('not on'));
    final ios = networkBlockNote(os: 'ios');
    expect(ios, allOf(contains('Mobile Data'), contains('Cellular'), contains('aeroplane mode')));
  });
}
