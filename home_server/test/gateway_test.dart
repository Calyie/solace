// The gateway with a stand-in model (no llama-server): pairing, pinning, tokens, the slot each device gets, streaming,
// a phone that goes away, limits, unpairing, and the llama-server command line that keeps nothing. Run with
// `dart test` in home_server/ (openssl makes the test certificate).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../app/home/home_protocol.dart';
import '../src/solace_home.dart';

/// The model, stood in: records the slot and the request, and streams words at the pace asked.
class FakeUpstream implements Upstream {
  @override
  bool ready = true;
  final slots = <int>[];
  final requests = <ChatRequest>[];
  int aborted = 0;
  Duration pace = Duration.zero;
  Duration firstWord = Duration.zero;
  List<String> words = ['Hello', ' there', '.'];

  /// After this many words the stream fails, as llama-server's does when it stops before [DONE] (null: never).
  int? failAfter;

  @override
  Future<UpstreamReply> chat(ChatRequest request, int slot) async {
    if (!ready) throw const UpstreamDown();
    slots.add(slot);
    requests.add(request);
    var stop = false;
    final out = StreamController<String>();
    unawaited(() async {
      await Future<void>.delayed(firstWord);
      var n = 0;
      for (final w in words) {
        if (stop) break;
        if (failAfter != null && n++ >= failAfter!) {
          out.addError(const UpstreamFailed(502));
          break;
        }
        out.add(w);
        await Future<void>.delayed(pace);
      }
      if (!out.isClosed) await out.close();
    }());
    return UpstreamReply(out.stream, () {
      if (!stop) aborted++;
      stop = true;
      if (!out.isClosed) unawaited(out.close());
    });
  }
}

late Directory tmp;
late Certificate cert;

final model = ServedModel(file: File('/m/therapist-e4b-Q5_K_M-imat.gguf'),
    sha256: 'f11adf75e1a8bce465fbda2dacef5dd788af0f8cc5c67e9e9097f180e4f69882', size: 5, light: false,
    trustedBy: 'built-in');

class Rig {
  Rig({Limits limits = const Limits()})
      : upstream = FakeUpstream(),
        devices = DeviceStore(File('${tmp.path}/devices-${DateTime.now().microsecondsSinceEpoch}.json')) {
    pairing = Pairing(Random(7));
    gateway = Gateway(devices: devices, pairing: pairing, upstream: upstream, model: model,
        fingerprint: cert.fingerprint, limits: limits, random: Random(3), onDevicesChanged: () async => changes++);
  }
  final FakeUpstream upstream;
  final DeviceStore devices;
  late final Pairing pairing;
  late final Gateway gateway;
  int changes = 0;

  Future<void> start() => gateway.bind(cert.context(), address: '127.0.0.1', port: 0);

  HttpClient client({String? pin}) {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.badCertificateCallback = (x, _, _) => pin == null || certificateFingerprint(x.der) == pin;
    return c;
  }

  Future<(int, Object?)> send(String method, String path, {String? token, Object? body, String? raw}) async {
    final c = client(pin: cert.fingerprint);
    try {
      final req = await c.openUrl(method, Uri.parse('https://127.0.0.1:${gateway.port}$path'));
      if (token != null) req.headers.set('authorization', 'Bearer $token');
      if (body != null || raw != null) {
        req.headers.contentType = ContentType.json;
        req.write(raw ?? jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      Object? j;
      try {
        j = jsonDecode(text);
      } on FormatException {
        j = text;
      }
      return (res.statusCode, j);
    } finally {
      c.close(force: true);
    }
  }

  /// Pairs as a phone would; returns the token (and checks the server's proof).
  Future<String> pair(String code, {String name = 'Test phone'}) async {
    final (s1, j1) = await send('POST', pairStartPath, body: {});
    expect(s1, 200, reason: '$j1');
    final ns = (j1 as Map)['server_nonce'] as String;
    const np = 'phone-nonce-0123456789abcdef';
    final proof = pairProof(code, 'phone', fingerprint: cert.fingerprint, serverNonce: ns, phoneNonce: np);
    final (s2, j2) = await send('POST', pairFinishPath,
        body: {'protocol': homeProtocol, 'server_nonce': ns, 'phone_nonce': np, 'name': name, 'proof': proof});
    expect(s2, 200, reason: '$j2');
    final m = j2 as Map;
    final token = m['token'] as String;
    expect(m['proof'], pairProof(code, 'server', fingerprint: cert.fingerprint, serverNonce: ns, phoneNonce: np,
        deviceId: m['device_id'] as String, tokenSha: tokenHash(token)));
    return token;
  }

  Future<(int, String)> chat(String token, {Object? body}) async {
    final c = client(pin: cert.fingerprint);
    try {
      final req = await c.postUrl(Uri.parse('https://127.0.0.1:${gateway.port}$chatPath'));
      req.headers.set('authorization', 'Bearer $token');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body ?? {'messages': [{'role': 'user', 'content': 'hi'}], 'max_tokens': 20}));
      final res = await req.close();
      return (res.statusCode, await utf8.decoder.bind(res).join());
    } finally {
      c.close(force: true);
    }
  }
}

List<String> words(String sse) => [
      for (final line in const LineSplitter().convert(sse))
        if (line.startsWith('data: {') && line.contains('"content"'))
          ((jsonDecode(line.substring(6)) as Map)['choices'] as List).first['delta']['content'] as String,
    ];

void main() {
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('solace_home_test');
    cert = await Certificate.inDir(tmp);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  test('the certificate is made once, private, and its fingerprint is the SHA-256 of its DER bytes', () async {
    final again = await Certificate.inDir(tmp);
    expect(again.fingerprint, cert.fingerprint);
    expect(cert.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    final mode = (await Process.run('stat', ['-c', '%a', cert.keyFile.path])).stdout.toString().trim();
    expect(mode, '600');
  });

  group('pairing', () {
    test('a phone with the right code pairs; its token works, and the server keeps only the token\'s hash', () async {
      final r = Rig();
      await r.start();
      final code = r.pairing.open();
      final token = await r.pair(code);
      expect(r.devices.devices, hasLength(1));
      expect(r.changes, 1, reason: 'llama-server is restarted with one slot per device');
      final kept = await r.devices.file!.readAsString();
      expect(kept, isNot(contains(token)));
      expect(kept, contains(tokenHash(token)));
      final (s, j) = await r.send('GET', statusPath, token: token);
      expect(s, 200);
      expect(((j as Map)['model'] as Map)['sha256'], model.sha256);
      await r.gateway.close();
    });

    test('pairing is refused when no window is open, and one code pairs one device only', () async {
      final r = Rig();
      await r.start();
      final (s, _) = await r.send('POST', pairStartPath, body: {});
      expect(s, 403);
      final code = r.pairing.open();
      await r.pair(code);
      final (s2, _) = await r.send('POST', pairStartPath, body: {});
      expect(s2, 403, reason: 'the window closed with the first pairing');
      await r.gateway.close();
    });

    test('a wrong code is refused; five wrong proofs shut out that address only, never the owner (H19-09)', () async {
      final r = Rig();
      await r.start();
      final code = r.pairing.open();
      for (var i = 0; i < 5; i++) {
        final (_, j) = await r.send('POST', pairStartPath, body: {});
        final ns = (j as Map)['server_nonce'] as String;
        final proof = pairProof('ABCDEFGHJKLM', 'phone', fingerprint: cert.fingerprint, serverNonce: ns,
            phoneNonce: 'phone-nonce-0123456789abcdef');
        final (s, _) = await r.send('POST', pairFinishPath, body: {'protocol': homeProtocol, 'server_nonce': ns,
          'phone_nonce': 'phone-nonce-0123456789abcdef', 'name': 'x', 'proof': proof});
        expect(s, 403);
      }
      // this address may not try again in this window; the window stays open for everyone else
      expect((await r.send('POST', pairStartPath, body: {})).$1, 429);
      expect(r.pairing.isOpen, isTrue, reason: 'a stranger\'s wrong proofs no longer close the owner\'s window');
      expect(r.devices.devices, isEmpty);
      expect(code, hasLength(codeLength));
      // and the owner can always open a new window (a new code, counts cleared) from the server's terminal
      await r.pair(r.pairing.open());
      expect(r.devices.devices, hasLength(1));
      await r.gateway.close();
    });

    test('while every nonce is taken, a phone is told pairing is busy (503), not that it is closed', () async {
      final r = Rig();
      await r.start();
      r.pairing.open();
      for (var i = 0; i < Pairing.mostNonces; i++) {
        expect(r.pairing.start('10.0.${i ~/ 2}.1').$1, isNotNull);
      }
      final (s, j) = await r.send('POST', pairStartPath, body: {});
      expect(s, 503);
      expect('$j', contains('busy'));
      await r.gateway.close();
    });

    test('a proof made over another certificate (a machine in the middle) is refused, though the code is right',
        () async {
      final r = Rig();
      await r.start();
      final code = r.pairing.open();
      final (_, j) = await r.send('POST', pairStartPath, body: {});
      final ns = (j as Map)['server_nonce'] as String;
      final proof = pairProof(code, 'phone', fingerprint: 'f' * 64, serverNonce: ns,
          phoneNonce: 'phone-nonce-0123456789abcdef');
      final (s, _) = await r.send('POST', pairFinishPath, body: {'protocol': homeProtocol, 'server_nonce': ns,
        'phone_nonce': 'phone-nonce-0123456789abcdef', 'name': 'x', 'proof': proof});
      expect(s, 403);
      expect(r.devices.devices, isEmpty);
      await r.gateway.close();
    });

    test('a server nonce works once only', () async {
      final r = Rig();
      await r.start();
      final code = r.pairing.open();
      final (_, j) = await r.send('POST', pairStartPath, body: {});
      final ns = (j as Map)['server_nonce'] as String;
      final body = {'protocol': homeProtocol, 'server_nonce': ns, 'phone_nonce': 'phone-nonce-0123456789abcdef',
        'name': 'x', 'proof': 'wrong'};
      expect((await r.send('POST', pairFinishPath, body: body)).$1, 403);
      body['proof'] = pairProof(code, 'phone', fingerprint: cert.fingerprint, serverNonce: ns,
          phoneNonce: 'phone-nonce-0123456789abcdef');
      expect((await r.send('POST', pairFinishPath, body: body)).$1, 403, reason: 'the nonce was used');
      await r.gateway.close();
    });

    test('at most four devices', () async {
      final r = Rig();
      await r.start();
      for (var i = 0; i < 4; i++) {
        await r.pair(r.pairing.open(), name: 'phone $i');
      }
      r.pairing.open();
      final (s, j) = await r.send('POST', pairStartPath, body: {});
      expect(s, 403);
      expect('$j', contains('4 devices'));
      await r.gateway.close();
    });
  });

  group('requests', () {
    late Rig r;
    late String token;
    setUp(() async {
      r = Rig();
      await r.start();
      token = await r.pair(r.pairing.open());
    });
    tearDown(() => r.gateway.close());

    test('a wrong or missing token is refused', () async {
      expect((await r.send('GET', statusPath)).$1, 401);
      expect((await r.send('GET', statusPath, token: 'x' * 43)).$1, 401);
      expect((await r.chat('y' * 43)).$1, 401);
      expect(r.upstream.requests, isEmpty);
    });

    test('ten refused requests from one address block its tries without a token for ten minutes; a paired device '
        'on that address is still served (H19-02)', () async {
      for (var i = 0; i < 10; i++) {
        await r.send('GET', statusPath, token: 'bad$i' * 10);
      }
      expect((await r.send('GET', statusPath, token: 'another' * 10)).$1, 429);
      expect((await r.send('POST', pairStartPath, body: {})).$1, 429);
      expect((await r.send('GET', statusPath, token: token)).$1, 200);
      expect((await r.chat(token)).$1, 200);
    });

    test('the reply streams as OpenAI-style events, in the device\'s own slot, naming the model it came from',
        () async {
      final second = await r.pair(r.pairing.open(), name: 'tablet');
      final (s, body) = await r.chat(token);
      expect(s, 200);
      expect(words(body), ['Hello', ' there', '.']);
      expect(body, contains('"finish_reason":"stop"'));
      expect(body.trim(), endsWith('data: [DONE]'));
      await r.chat(second);
      expect(r.upstream.slots, [0, 1], reason: 'one slot per device');
      // H19-08: every reply and status says which model's SHA-256 wrote it, so the phone can check it each time
      final c = r.client(pin: cert.fingerprint);
      final req = await c.postUrl(Uri.parse('https://127.0.0.1:${r.gateway.port}$chatPath'));
      req.headers.set('authorization', 'Bearer $token');
      req.write(jsonEncode({'messages': [{'role': 'user', 'content': 'hi'}]}));
      final res = await req.close();
      expect(res.headers.value(servedModelHeader), model.sha256);
      await res.drain<void>();
      final st = await (await c.getUrl(Uri.parse('https://127.0.0.1:${r.gateway.port}$statusPath'))
        ..headers.set('authorization', 'Bearer $token')).close();
      expect(st.headers.value(servedModelHeader), model.sha256);
      await st.drain<void>();
      c.close(force: true);
    });

    test('a model that stops before its end gives an error event and never [DONE] (H19-03)', () async {
      r.upstream
        ..words = ['one ', 'two ', 'three ', 'four ']
        ..failAfter = 2;
      final (s, body) = await r.chat(token);
      expect(s, 200);
      expect(words(body), ['one ', 'two ']);
      expect(body, contains('"error"'));
      expect(body, isNot(contains('[DONE]')));
    });

    test('a reader that pauses mid-reply gets every word and [DONE]: pings never cut the reply (H19-03)', () async {
      // big pieces, so the connection's buffers fill while the reader pauses and a write's flush stays pending while
      // pings fall due (every 50 ms here); before the fix a ping's write then threw and the reply was cut
      final rig = Rig(limits: const Limits(ping: Duration(milliseconds: 50)));
      await rig.start();
      final t = await rig.pair(rig.pairing.open());
      rig.upstream
        ..words = [for (var i = 0; i < 300; i++) '${'w' * 64000}$i ']
        ..pace = const Duration(milliseconds: 1);
      final c = rig.client(pin: cert.fingerprint);
      final req = await c.postUrl(Uri.parse('https://127.0.0.1:${rig.gateway.port}$chatPath'));
      req.headers.set('authorization', 'Bearer $t');
      req.write(jsonEncode({'messages': [{'role': 'user', 'content': 'hi'}]}));
      final res = await req.close();
      final got = BytesBuilder();
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      var paused = false;
      sub = res.listen((chunk) {
        got.add(chunk);
        if (!paused) {
          paused = true;
          sub.pause(Future<void>.delayed(const Duration(seconds: 3)));
        }
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 60));
      c.close(force: true);
      final body = utf8.decode(got.takeBytes());
      expect(words(body), hasLength(300));
      expect(body.trim(), endsWith('data: [DONE]'));
      expect(rig.upstream.aborted, 0, reason: 'the model was never stopped');
      await rig.gateway.close();
    });

    test('only the conversation and the reply length reach the model; anything else is refused', () async {
      await r.chat(token, body: {'messages': [{'role': 'system', 'content': 's'}, {'role': 'user', 'content': 'u'}],
        'max_tokens': 7});
      expect(r.upstream.requests.single.messages, [{'role': 'system', 'content': 's'}, {'role': 'user', 'content': 'u'}]);
      expect(r.upstream.requests.single.maxTokens, 7);
      for (final bad in [
        {'messages': [{'role': 'user', 'content': 'u'}], 'id_slot': 3},
        {'messages': [{'role': 'user', 'content': 'u'}], 'grammar': 'x'},
        {'messages': [{'role': 'tool', 'content': 'u'}]},
        {'messages': [{'role': 'user', 'content': 'u', 'extra': 1}]},
        {'messages': [{'role': 'user', 'content': 'u'}], 'max_tokens': 100000},
        {'messages': <Object>[]},
      ]) {
        expect((await r.chat(token, body: bad)).$1, 400, reason: '$bad');
      }
      expect(r.upstream.requests, hasLength(1));
    });

    test('a body over the limit is refused before the model sees it (and before it is read)', () async {
      int? status;
      try {
        status = (await r.chat(token, body: {'messages': [{'role': 'user', 'content': 'x' * (300 * 1024)}]})).$1;
      } on HttpException {
        status = null; // the gateway answered 413 and closed before the client finished sending: refused either way
      } on SocketException {
        status = null;
      }
      expect(status, anyOf(isNull, 413));
      expect(r.upstream.requests, isEmpty);
    });

    test('a phone that goes away stops the model at once', () async {
      r.upstream
        ..firstWord = const Duration(seconds: 2)
        ..words = List.filled(200, ' word')
        ..pace = const Duration(milliseconds: 20);
      final c = r.client(pin: cert.fingerprint);
      final req = await c.postUrl(Uri.parse('https://127.0.0.1:${r.gateway.port}$chatPath'));
      req.headers.set('authorization', 'Bearer $token');
      req.write(jsonEncode({'messages': [{'role': 'user', 'content': 'hi'}]}));
      final res = await req.close();
      final sub = res.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await sub.cancel();
      c.close(force: true);
      // noticed at the next word or the next ping (every 5 seconds while the prompt is read)
      for (var i = 0; i < 70 && r.upstream.aborted == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(r.upstream.aborted, 1);
    });

    test('a newer request from the same device replaces the one before', () async {
      r.upstream
        ..words = List.filled(100, ' w')
        ..pace = const Duration(milliseconds: 50);
      final first = r.chat(token);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      r.upstream
        ..words = ['new']
        ..pace = Duration.zero;
      final (_, body) = await r.chat(token);
      expect(words(body), ['new']);
      expect(r.upstream.aborted, 1);
      await first;
    });

    test('while the model loads, a request is told to wait (503)', () async {
      r.upstream.ready = false;
      expect((await r.chat(token)).$1, 503);
    });

    test('more than 60 requests a minute from one device are slowed (429)', () async {
      final limited = Rig(limits: const Limits(requestsPerMinute: 3));
      await limited.start();
      final t = await limited.pair(limited.pairing.open());
      final statuses = [for (var i = 0; i < 4; i++) (await limited.send('GET', statusPath, token: t)).$1];
      expect(statuses, [200, 200, 200, 429]);
      await limited.gateway.close();
    });

    test('unpair: the device forgets itself, its token stops working, and the slots are made again', () async {
      final before = r.changes;
      expect((await r.send('POST', unpairPath, token: token)).$1, 200);
      expect(r.devices.devices, isEmpty);
      expect((await r.send('GET', statusPath, token: token)).$1, 401);
      expect(r.changes, before + 1);
    });

    test('nothing about a request is written: the folder holds only the certificate, the device list and config',
        () async {
      await r.chat(token, body: {'messages': [{'role': 'user', 'content': 'my private words'}]});
      for (final f in tmp.listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains('my private words')), reason: f.path);
        expect(f.uri.pathSegments.last, matches(RegExp(r'^(cert\.pem|key\.pem|devices-\d+\.json)$')));
      }
    });
  });

  group('strangers cannot starve paired devices (H19-02)', () {
    test('33 connections holding a pairing body open: the paired device is still served at once, and each stalled '
        'body is cut at its deadline', () async {
      // the reviewer's reproduction: before the fix, every request then got 503 "busy" for as long as they were held
      final r = Rig(limits: const Limits(smallBodyTime: Duration(seconds: 2), connectionsPerAddress: 100));
      await r.start();
      final token = await r.pair(r.pairing.open());
      final held = <SecureSocket>[];
      final answers = <Future<String>>[];
      for (var i = 0; i < 33; i++) {
        final s = await SecureSocket.connect('127.0.0.1', r.gateway.port, onBadCertificate: (_) => true);
        s.write('POST $pairFinishPath HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n'
            'Content-Length: 4000\r\n\r\n{');
        await s.flush();
        held.add(s);
        answers.add(utf8.decoder.bind(s).join().timeout(const Duration(seconds: 20), onTimeout: () => 'held'));
      }
      final sw = Stopwatch()..start();
      final (status, _) = await r.send('GET', statusPath, token: token);
      expect(status, 200);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect((await r.chat(token)).$1, 200, reason: 'a chat too');
      // every stalled request was answered and its connection closed: 429 or 503 at once, 408 at its deadline
      final said = await Future.wait(answers);
      expect(said.where((a) => a == 'held'), isEmpty);
      expect(said.where((a) => a.contains(' 408 ')), isNotEmpty, reason: 'the ones being read were cut at 2 s');
      expect(said.every((a) => RegExp(r'HTTP/1.1 (408|429|503) ').hasMatch(a)), isTrue, reason: said.toSet().join());
      for (final s in held) {
        s.destroy();
      }
      await r.gateway.close();
    });

    test('a connection that never finishes its TLS handshake is closed at the deadline; at most so many from one '
        'address at once', () async {
      final r = Rig(limits: const Limits(handshake: Duration(milliseconds: 800), connectionsPerAddress: 4));
      await r.start();
      final raw = [for (var i = 0; i < 6; i++) await Socket.connect('127.0.0.1', r.gateway.port)];
      final closed = [for (final s in raw) s.drain<void>().then((_) => true, onError: (Object _) => true)];
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(r.gateway.listener.openFrom('127.0.0.1'), 4, reason: 'the fifth and sixth were closed at once');
      await Future.wait(closed).timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(r.gateway.listener.open, 0, reason: 'all given back once closed');
      final token = await r.pair(r.pairing.open());
      expect((await r.send('GET', statusPath, token: token)).$1, 200);
      await r.gateway.close();
    });

    test('a request that sends its headers too slowly is closed', () async {
      final r = Rig(limits: const Limits(headers: Duration(milliseconds: 500)));
      await r.start();
      final s = await SecureSocket.connect('127.0.0.1', r.gateway.port, onBadCertificate: (_) => true);
      s.write('POST $pairStartPath HTTP/1.1\r\nHost: x\r\n'); // and never the end of the headers
      await s.flush();
      final sw = Stopwatch()..start();
      await s.drain<void>().timeout(const Duration(seconds: 5), onTimeout: () => fail('still open'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      await r.gateway.close();
    });

    test('requests without a valid token share a small allowance; a body is read only up to its limit', () async {
      final r = Rig(limits: const Limits(strangerRequestsPerMinute: 3));
      await r.start();
      final statuses = [for (var i = 0; i < 4; i++) (await r.send('POST', pairStartPath, body: {})).$1];
      expect(statuses, [403, 403, 403, 429], reason: 'pairing closed, then too many from this address');
      await r.gateway.close();
      final big = Rig();
      await big.start();
      big.pairing.open();
      int? status;
      try {
        status = (await big.send('POST', pairStartPath, raw: '{"x":"${'y' * 10000}"}')).$1;
      } on SocketException {
        status = null;
      } on HttpException {
        status = null;
      }
      expect(status, anyOf(isNull, 413));
      await big.gateway.close();
    });
  });

  group('pairing limits by address (H19-09)', () {
    test('two nonces at once per address; others still get theirs', () {
      final p = Pairing(Random(1))..open();
      expect(p.start('10.0.0.1').$1, isNotNull);
      expect(p.start('10.0.0.1').$1, isNotNull);
      expect(p.start('10.0.0.1').$2, PairRefused.tooMany);
      expect(p.start('10.0.0.2').$1, isNotNull);
    });

    test('a stranger\'s wrong proofs shut out the stranger, and the owner\'s phone still pairs', () {
      final p = Pairing(Random(1));
      final code = p.open();
      for (var i = 0; i < Pairing.mostWrongPerAddress; i++) {
        final (n, _) = p.start('203.0.113.9');
        expect(p.check(serverNonce: n!, phoneNonce: 'n' * 20, name: 'x', proof: 'wrong', fingerprint: 'f' * 64,
            from: '203.0.113.9').$2, PairRefused.wrong);
      }
      expect(p.start('203.0.113.9').$2, PairRefused.tooMany);
      final (n, _) = p.start('192.168.1.5');
      final proof = pairProof(code, 'phone', fingerprint: 'f' * 64, serverNonce: n!, phoneNonce: 'n' * 20);
      expect(p.check(serverNonce: n, phoneNonce: 'n' * 20, name: 'phone', proof: proof, fingerprint: 'f' * 64,
          from: '192.168.1.5').$1, isNotNull);
    });

    test('a nonce left to expire counts as a wrong try for the address that took it', () {
      var now = DateTime(2026, 11, 19, 12);
      final p = Pairing(Random(1), clock: () => now)..open();
      // five nonces taken and left (two at a time, the most one address may hold), in under the window's 10 minutes
      for (var i = 0; i < Pairing.mostWrongPerAddress; i++) {
        expect(p.start('203.0.113.9').$1, isNotNull);
        if (i.isOdd || i == Pairing.mostWrongPerAddress - 1) now = now.add(Pairing.nonceLasts + const Duration(seconds: 1));
      }
      expect(p.isOpen, isTrue);
      expect(p.start('203.0.113.9').$2, PairRefused.tooMany);
      expect(p.start('192.168.1.5').$1, isNotNull);
    });
  });

  group('fixed slots (H19-17)', () {
    test('a device keeps its slot when another is unpaired; a new device takes the lowest free one', () async {
      final r = Rig();
      await r.start();
      final a = await r.pair(r.pairing.open(), name: 'a');
      final b = await r.pair(r.pairing.open(), name: 'b');
      final c = await r.pair(r.pairing.open(), name: 'c');
      expect([for (final d in r.devices.devices) d.slot], [0, 1, 2]);
      expect(await r.gateway.unpair([r.devices.byToken(a)!.id]), 1);
      expect(r.devices.slotOf(r.devices.byToken(b)!), 1);
      expect(r.devices.slotOf(r.devices.byToken(c)!), 2);
      expect(r.devices.slotsNeeded, 3, reason: 'slot 2 is still in use');
      await r.chat(c);
      expect(r.upstream.slots.last, 2);
      await r.pair(r.pairing.open(), name: 'd');
      expect(r.devices.devices.last.slot, 0);
      // kept in devices.json, and read back as kept
      final again = DeviceStore(r.devices.file!);
      await again.load();
      expect([for (final d in again.devices) (d.name, d.slot)], [('b', 1), ('c', 2), ('d', 0)]);
      await r.gateway.close();
    });

    test('a list from the earlier version (no slots) gets one slot each, in order; a slot given twice is fixed',
        () async {
      final f = File('${tmp.path}/old-devices.json');
      String dev(String id, [int? slot]) => jsonEncode({'id': id, 'name': id, 'token_sha256': 'a' * 64,
        'paired': '2026-11-19', 'slot': ?slot});
      await writePrivate(f, '{"devices":[${dev('device-one')},${dev('device-two', 0)},${dev('device-three', 0)}]}');
      final d = DeviceStore(f);
      await d.load();
      expect([for (final x in d.devices) x.slot], [1, 0, 2]);
      await f.delete();
    });

    test('unpairing from the server\'s terminal stops that device\'s running reply at once', () async {
      final r = Rig();
      await r.start();
      final t = await r.pair(r.pairing.open());
      r.upstream
        ..words = List.filled(500, ' w')
        ..pace = const Duration(milliseconds: 20);
      final reply = r.chat(t);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await r.gateway.unpair([r.devices.devices.single.id]);
      expect(r.upstream.aborted, 1);
      final (_, body) = await reply;
      expect(body, isNot(contains('[DONE]')));
      await r.gateway.close();
    });
  });

  group('private files (H19-18)', () {
    test('the folder is made 700 and files 600, checked; a file that cannot be made private is refused', () async {
      final d = Directory('${tmp.path}/private-check');
      await ensurePrivateDir(d);
      expect((await FileStat.stat(d.path)).mode & 0x1ff, 0x1c0);
      final f = File('${d.path}/x.json');
      await writePrivate(f, '{}');
      expect((await FileStat.stat(f.path)).mode & 0x1ff, 0x180);
      // a file chmod cannot change (not this user's): refused, never used as if it were private
      final theirs = ['/etc/hostname', '/etc/passwd'].firstWhere((p) => File(p).existsSync());
      await expectLater(makePrivate(theirs, 0x180), throwsA(isA<NotPrivate>()));
      // a mode that did not take (as on a file system that ignores modes) is refused by the check
      await Process.run('chmod', ['644', f.path]);
      await expectLater(checkPrivate(f.path, 0x180), throwsA(isA<NotPrivate>()));
      await d.delete(recursive: true);
    });
  });

  group('llama-server', () {
    final c = HomeConfig(model: '/m/model.gguf', llamaServer: '/opt/llama-server');
    const sock = '/home/x/.config/solace-home/llama.sock';

    test('one slot per device, 8,192 tokens each, on a Unix socket with no TCP port, keeping nothing', () {
      final args = llamaArgs(c, 3, sock);
      String after(String flag) => args[args.indexOf(flag) + 1];
      expect(after('--host'), sock, reason: 'H19-01: a Unix socket in the private folder');
      expect(args, isNot(contains('--port')));
      expect(after('-np'), '3');
      expect(after('-c'), '${8192 * 3}');
      expect(args, containsAll(['--no-kv-unified', '--log-disable', '--no-slots', '--no-webui', '--offline',
          '--no-cache-idle-slots']));
      expect(after('--cache-ram'), '0');
      for (final never in ['--metrics', '--slot-save-path', '--log-file', '--api-key', '--props', '--tools',
          '--webui-mcp-proxy', '--mlock']) {
        expect(args.any((a) => a.startsWith(never)), isFalse, reason: never);
      }
      expect(llamaArgs(HomeConfig(model: 'm', llamaServer: 'l', mlock: true), 1, sock), contains('--mlock'));
    });

    test('it is started with its core limit at 0 (H19-10)', () {
      final (exe, args) = llamaCommand(c, 1, sock);
      expect(exe, '/bin/sh');
      expect(args.take(3), ['-c', r'ulimit -c 0 && exec "$0" "$@"', '/opt/llama-server']);
      expect(args.skip(3), llamaArgs(c, 1, sock));
    });

    test('it starts with none of the computer\'s environment but its path and graphics settings, and a fresh key',
        () {
      final env = llamaEnvironment('k', {'PATH': '/bin', 'HOME': '/h', 'LLAMA_ARG_SLOT_SAVE_PATH': '/tmp/x',
        'LLAMA_ARG_ENDPOINT_METRICS': '1', 'CUDA_VISIBLE_DEVICES': '0', 'SECRET': 's'});
      expect(env, {'LLAMA_API_KEY': 'k', 'PATH': '/bin', 'HOME': '/h', 'CUDA_VISIBLE_DEVICES': '0'});
    });

    test('its event stream is read word by word; an error in it, or an end without [DONE], is an error', () async {
      Stream<List<int>> body(String s) => Stream.value(utf8.encode(s));
      final got = await LlamaServer.pieces(body('data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":" you"}}]}\n\ndata: [DONE]\n\n')).toList();
      expect(got, ['Hi', ' you']);
      expect(LlamaServer.pieces(body('data: {"error":{"message":"x"}}\n\n')).toList(), throwsA(isA<UpstreamFailed>()));
      expect(LlamaServer.pieces(body('data: {"choices":[{"delta":{"content":"cut"}}]}\n\n')).toList(),
          throwsA(isA<UpstreamFailed>()), reason: 'H19-03: llama-server stopped before its end');
      expect(LlamaServer.pieces(body('data: ${'x' * 100}'), mostLine: 50).toList(), throwsA(isA<LineTooLong>()));
    });

    test('the gateway turns core dumps off for itself, and its children inherit it (H19-10)', () async {
      final off = noCoreDumps();
      expect(off.limitZero, isTrue);
      if (Platform.isLinux) expect(off.notDumpable, isTrue);
      final child = await Process.run('/bin/sh', ['-c', 'ulimit -c; ulimit -H -c']);
      expect('${child.stdout}'.trim().split('\n'), ['0', '0']);
    });
  });

  group('llama-server started and kept running (stand-in, no model)', () {
    late Directory dir;
    late String fake, failing;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('solace_llama');
      await ensurePrivateDir(dir);
      final script = File('test/support/fake_llama_server.dart').absolute.path;
      fake = '${dir.path}/llama-server';
      File(fake).writeAsStringSync('#!/bin/sh\nexec "${Platform.resolvedExecutable}" "$script" "\$@"\n');
      failing = '${dir.path}/llama-server-fails';
      File(failing).writeAsStringSync('#!/bin/sh\nsleep 1\nexit 1\n');
      await Process.run('chmod', ['755', fake, failing]);
    });
    tearDownAll(() => dir.delete(recursive: true));

    Future<void> until(bool Function() ok, {Duration within = const Duration(seconds: 30)}) async {
      final end = DateTime.now().add(within);
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('it is reached on its Unix socket only, with its key; a slot it was not started with is never sent '
        '(H19-01, H19-17)', () async {
      var slots = 2;
      final llama = LlamaServer(HomeConfig(model: '/m/x.gguf', llamaServer: fake), socket: '${dir.path}/llama.sock',
          slots: () => slots);
      llama.keepRunning();
      await until(() => llama.ready);
      expect((await FileStat.stat('${dir.path}/llama.sock')).type, FileSystemEntityType.unixDomainSock);
      expect((await FileStat.stat('${dir.path}/llama.sock')).mode & 0x1ff, 0x180, reason: 'made private, checked');
      final reply = await llama.chat(ChatRequest([{'role': 'user', 'content': 'hi'}], 5), 1);
      expect((await reply.pieces.toList()).join(), 'slot 1 of 2');
      await expectLater(llama.chat(ChatRequest([{'role': 'user', 'content': 'hi'}], 5), 2),
          throwsA(isA<UpstreamDown>()));
      // its core limit is 0 (Linux shows it in /proc)
      if (Platform.isLinux) {
        final c = unixClient('${dir.path}/llama.sock');
        final res = await (await c.getUrl(Uri.parse('http://llama-server/limits'))).close();
        expect(await utf8.decoder.bind(res).join(), matches(RegExp(r'^Max core file size\s+0\s+0\s')));
        c.close(force: true);
      }
      // a pairing change: refused at once (503), then ready again with the new slots
      slots = 3;
      llama.restart();
      expect(llama.ready, isFalse);
      await expectLater(llama.chat(ChatRequest([{'role': 'user', 'content': 'hi'}], 5), 0),
          throwsA(isA<UpstreamDown>()));
      await until(() => llama.ready);
      expect(llama.slots, 3);
      await llama.stop();
      expect(File('${dir.path}/llama.sock').existsSync(), isFalse);
    });

    test('a start that fails is tried again with a growing pause; whatever answers on 127.0.0.1 is never asked '
        '(H19-01, H19-11)', () async {
      // the reviewer's squatter: a server on 127.0.0.1 answering /health; it is never reached any more
      final squatter = await HttpServer.bind('127.0.0.1', 0);
      var asked = 0;
      squatter.listen((r) {
        asked++;
        r.response.close();
      });
      final llama = LlamaServer(HomeConfig(model: '/m/x.gguf', llamaServer: failing),
          socket: '${dir.path}/llama-f.sock', firstPause: const Duration(milliseconds: 200));
      llama.keepRunning();
      await until(() => llama.starts >= 3, within: const Duration(seconds: 20));
      expect(llama.ready, isFalse);
      expect(llama.problem, contains('stopped while loading'));
      expect(llama.describe, contains('next try in'));
      expect(asked, 0);
      await llama.stop();
      await squatter.close(force: true);
    });

    test('stopping while a restart is under way leaves no llama-server behind', () async {
      // the end-to-end run's case: a device unpaired, so llama-server restarts and the model is hashed again first,
      // and the gateway is stopped during that hash; before the fix a new llama-server started after stop() returned
      final sock = '${dir.path}/llama-s.sock';
      final llama = LlamaServer(HomeConfig(model: '/m/x.gguf', llamaServer: fake), socket: sock,
          beforeStart: () => Future<void>.delayed(const Duration(milliseconds: 700)));
      llama.keepRunning();
      await until(() => llama.ready);
      llama.restart();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await llama.stop();
      await Future<void>.delayed(const Duration(seconds: 3)); // past the hash and a start that would follow it
      final left = await Process.run('pgrep', ['-f', '--', '--host $sock']);
      expect('${left.stdout}'.trim(), isEmpty, reason: 'a llama-server was left running');
      expect(llama.ready, isFalse);
    });

    test('before every restart the model is checked again; a changed one is not served (H19-08)', () async {
      var checks = 0;
      var changed = false;
      final llama = LlamaServer(HomeConfig(model: '/m/x.gguf', llamaServer: fake), socket: '${dir.path}/llama-h.sock',
          firstPause: const Duration(milliseconds: 200), beforeStart: () async {
        checks++;
        if (changed) throw ModelRefused('x.gguf changed since solace-home serve started');
      });
      llama.keepRunning();
      await until(() => llama.ready);
      expect(checks, 0, reason: 'the first start uses the check serve just made');
      changed = true;
      llama.restart();
      await until(() => llama.problem != null);
      expect(llama.ready, isFalse);
      expect(llama.problem, contains('changed since'));
      expect(checks, greaterThanOrEqualTo(1));
      changed = false;
      await until(() => llama.ready);
      await llama.stop();
    });
  });

  group('solace-home unpair while the server is stopped (H19-11)', () {
    test('the device list on disk is changed directly', () async {
      final f = File('${tmp.path}/devices-offline.json');
      final store = DeviceStore(f);
      final (d, _) = await store.add('phone', Random(9));
      final dir = await Directory.systemTemp.createTemp('solace_home_cli');
      await ensurePrivateDir(dir);
      await f.copy('${dir.path}/devices.json');
      await f.delete();
      final r = await Process.run(Platform.resolvedExecutable, ['bin/solace_home.dart', 'unpair', d.id],
          environment: {'SOLACE_HOME_DIR': dir.path});
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}', contains('Unpaired 1 device(s)'));
      expect('${r.stdout}', contains('not running'));
      final after = DeviceStore(File('${dir.path}/devices.json'));
      await after.load();
      expect(after.devices, isEmpty);
      await dir.delete(recursive: true);
    });
  });
}
