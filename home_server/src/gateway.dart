// The gateway the phones reach (docs/HOME_SERVER.md section 4): TLS with the server's own certificate, pairing with a
// one-time code, a device token on every other request, one llama-server slot per device, the reply streamed as
// OpenAI-style server-sent events, limits on size, time and rate, and unpairing. It writes nothing about any request:
// no conversation, no prompt, no reply, no address, no time. What it sees, it sees in memory while it writes the reply.
//
// Strangers can never starve the paired devices (H19-02, H19-09): a request with a valid token is counted only
// against its own device (at most [Limits.atOncePerDevice] at once, [Limits.requestsPerMinute] a minute), never
// against strangers' limits and never blocked by an address's refused tries; everything else (pairing, a wrong or
// missing token) shares a small allowance of its own, [Limits.strangersAtOnce] at once and
// [Limits.strangersAtOncePerAddress] per address, [Limits.strangerRequestsPerMinute] a minute per address. Every
// body is read with a deadline and a size limit; connections, TLS handshakes and request headers have theirs in
// listener.dart and [Limits.headers].
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../app/home/home_protocol.dart';
import 'devices.dart';
import 'listener.dart';
import 'model_check.dart';
import 'pairing.dart';

/// The model behind the gateway: llama-server (llama.dart), or a stand-in in the tests.
abstract class Upstream {
  bool get ready;

  /// The reply's words to [request], generated in [slot]. Throws [UpstreamDown] when it cannot take requests.
  Future<UpstreamReply> chat(ChatRequest request, int slot);
}

class UpstreamReply {
  UpstreamReply(this.pieces, this.abort);
  final Stream<String> pieces;

  /// Stops the generation (the phone went away, or sent a newer request).
  final void Function() abort;
}

class UpstreamDown implements Exception {
  const UpstreamDown();
}

class UpstreamFailed implements Exception {
  const UpstreamFailed(this.status);
  final int status;
}

/// At most [most] events per key in any [window]; used for failures by address and requests by device.
class RateLimiter {
  RateLimiter(this.most, this.window, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final int most;
  final Duration window;
  final DateTime Function() clock;
  final _seen = <String, List<DateTime>>{};

  /// Counts one event for [key]; false when it is over the limit (and is not counted).
  bool take(String key) {
    final now = clock(), since = now.subtract(window);
    final list = _seen.putIfAbsent(key, () => []);
    list.removeWhere((t) => t.isBefore(since));
    if (list.length >= most) return false;
    list.add(now);
    if (_seen.length > 10000) _seen.removeWhere((_, v) => v.isEmpty || v.last.isBefore(since));
    return true;
  }

  /// True while [key] has reached the limit, without counting.
  bool blocked(String key) {
    final since = clock().subtract(window);
    final list = _seen[key];
    if (list == null) return false;
    list.removeWhere((t) => t.isBefore(since));
    return list.length >= most;
  }
}

class Limits {
  const Limits({this.chatBody = 256 * 1024, this.smallBody = 4096, this.requestsPerMinute = 60,
      this.atOncePerDevice = 4, this.strangerRequestsPerMinute = 30, this.strangersAtOnce = 8,
      this.strangersAtOncePerAddress = 2, this.failuresPerTenMinutes = 10, this.pairStartsPerMinute = 10,
      this.connections = 128, this.connectionsPerAddress = 16, this.handshake = const Duration(seconds: 5),
      this.headers = const Duration(seconds: 5), this.smallBodyTime = const Duration(seconds: 5),
      this.chatBodyTime = const Duration(seconds: 15), this.ping = const Duration(seconds: 5)});

  /// The largest request bodies: a conversation (the app's prompt is bounded to 8,192 tokens, well under this), and
  /// everything else.
  final int chatBody, smallBody;

  /// A paired device: requests a minute, and at once.
  final int requestsPerMinute, atOncePerDevice;

  /// Everyone else (pairing, a wrong or missing token): requests a minute per address, at once in all, and at once
  /// per address.
  final int strangerRequestsPerMinute, strangersAtOnce, strangersAtOncePerAddress;

  /// Refused tries from one address in ten minutes before its requests without a valid token are refused for ten
  /// minutes; pairing starts a minute per address.
  final int failuresPerTenMinutes, pairStartsPerMinute;

  /// Connections at once, in all and per address (listener.dart).
  final int connections, connectionsPerAddress;

  /// The TLS handshake's deadline; the time a connection has to send a request's headers (between this and twice
  /// this: the web server's idle timeout, which also closes a connection left idle); and the time a body has to
  /// arrive (anything but a conversation, and a conversation).
  final Duration handshake, headers, smallBodyTime, chatBodyTime;

  /// How often an event-stream comment is sent while no word goes out (the model reads the prompt): a phone that went
  /// away is noticed at the next one, and its generation stopped; the phone takes a long silence for a dead link.
  final Duration ping;
}

class Gateway {
  Gateway({required this.devices, required this.pairing, required this.upstream, required this.model,
      required this.fingerprint, this.limits = const Limits(), Random? random, this.onDevicesChanged,
      DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _failures = RateLimiter(limits.failuresPerTenMinutes, const Duration(minutes: 10), clock: clock),
        _pairStarts = RateLimiter(limits.pairStartsPerMinute, const Duration(minutes: 1), clock: clock),
        _requests = RateLimiter(limits.requestsPerMinute, const Duration(minutes: 1), clock: clock),
        _strangerRate = RateLimiter(limits.strangerRequestsPerMinute, const Duration(minutes: 1), clock: clock);

  final DeviceStore devices;
  final Pairing pairing;
  final Upstream upstream;
  final ServedModel model;

  /// The fingerprint of the certificate this gateway shows (the phone's proof is checked over it).
  final String fingerprint;
  final Limits limits;
  final Random _random;
  final RateLimiter _failures, _pairStarts, _requests, _strangerRate;

  /// Called after a device paired or was unpaired (main: restart llama-server with one slot per device).
  final Future<void> Function()? onDevicesChanged;

  final _active = <String, _Running>{}; // the generation running for each device
  final _atOnce = <String, int>{}; // requests in progress, by device
  final _strangersBy = <String, int>{}; // requests in progress without a valid token, by address
  int _strangers = 0;
  HttpServer? _server;
  GuardedListener? _listener;

  int get port => _listener!.port;

  /// The listening socket (the tests count its connections).
  GuardedListener get listener => _listener!;

  Future<void> bind(SecurityContext context, {String address = '0.0.0.0', int port = 8443}) async {
    final listener = await GuardedListener.bind(address, port, context, limits: ListenerLimits(
        connections: limits.connections, perAddress: limits.connectionsPerAddress, handshake: limits.handshake));
    final server = HttpServer.listenOn(listener)
      ..idleTimeout = limits.headers
      ..autoCompress = false
      ..serverHeader = null;
    _listener = listener;
    _server = server;
    server.listen((r) => unawaited(_handle(r)), onError: (Object _) {});
  }

  Future<void> close() async {
    for (final a in _active.values) {
      a.stop();
    }
    _active.clear();
    await _server?.close(force: true);
    await _listener?.close();
  }

  /// Removes the devices [ids] (`solace-home unpair`): each one's running reply stops at once and its token stops
  /// working; llama-server restarts without their slots. Returns how many there were.
  Future<int> unpair(Iterable<String> ids) async {
    var n = 0;
    for (final id in ids.toList()) {
      _active.remove(id)?.stop();
      if (await devices.remove(id)) n++;
    }
    if (n > 0) unawaited(onDevicesChanged?.call());
    return n;
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      r.response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      final path = r.uri.path;
      final pairingPath = path == pairStartPath || path == pairFinishPath;
      // a valid token first: a paired device is never held up by strangers, nor blocked by their refused tries
      final device = pairingPath ? null : _device(r);
      if (device != null) {
        await _forDevice(r, device, path);
      } else {
        await _forStranger(r, sourceOf(r.connectionInfo?.remoteAddress), path);
      }
    } catch (_) {
      // a phone that went away mid-request, or a malformed one: nothing to keep
      try {
        await r.response.close();
      } catch (_) {}
    }
  }

  Future<void> _forDevice(HttpRequest r, PairedDevice d, String path) async {
    final n = _atOnce[d.id] ?? 0;
    if (n >= limits.atOncePerDevice) return _refuse(r, 429, 'too many requests at once');
    _atOnce[d.id] = n + 1;
    try {
      if (!_requests.take(d.id)) return await _refuse(r, 429, 'too many requests; wait a minute');
      if (r.method == 'GET' && path == statusPath) return await _status(r, d);
      if (r.method == 'POST' && path == unpairPath) return await _unpair(r, d);
      if (r.method == 'POST' && path == chatPath) return await _chat(r, d);
      await _refuse(r, 404, 'no such path');
    } finally {
      final left = (_atOnce[d.id] ?? 1) - 1;
      left <= 0 ? _atOnce.remove(d.id) : _atOnce[d.id] = left;
    }
  }

  Future<void> _forStranger(HttpRequest r, String from, String path) async {
    if (_failures.blocked(from)) return _refuse(r, 429, 'too many refused requests; wait ten minutes');
    if (!_strangerRate.take(from)) return _refuse(r, 429, 'too many requests; wait a minute');
    final mine = _strangersBy[from] ?? 0;
    if (mine >= limits.strangersAtOncePerAddress) return _refuse(r, 429, 'too many requests at once');
    if (_strangers >= limits.strangersAtOnce) return _refuse(r, 503, 'busy; try again in a minute');
    _strangers++;
    _strangersBy[from] = mine + 1;
    try {
      if (r.method == 'POST' && path == pairStartPath) return await _pairStart(r, from);
      if (r.method == 'POST' && path == pairFinishPath) return await _pairFinish(r, from);
      _failures.take(from);
      // read (at most a conversation's size, with its deadline) so the phone sees the answer, not a reset
      await _body(r, limits.chatBody, limits.chatBodyTime);
      await _say(r, 401, 'not paired');
    } finally {
      _strangers--;
      final left = (_strangersBy[from] ?? 1) - 1;
      left <= 0 ? _strangersBy.remove(from) : _strangersBy[from] = left;
    }
  }

  PairedDevice? _device(HttpRequest r) {
    final h = r.headers.value(HttpHeaders.authorizationHeader);
    if (h == null || !h.startsWith('Bearer ') || h.length > 200) return null;
    return devices.byToken(h.substring(7).trim());
  }

  /// A refusal before anything else is read: a small body (a phone's) is read first for at most a second, so the
  /// phone sees the answer rather than a reset; anything larger or slower is left unread and the connection closed.
  Future<void> _refuse(HttpRequest r, int status, String message) async {
    await _body(r, limits.smallBody, const Duration(seconds: 1));
    await _say(r, status, message);
  }

  Future<void> _say(HttpRequest r, int status, String message, [Map<String, Object?>? body]) async {
    // a body nobody read is let go here: otherwise the web server reads all of it, with no deadline, before it sends
    // the answer (H19-02: a stalled body held every refused connection open)
    try {
      unawaited(r.listen(null).cancel().catchError((Object _) {}));
    } catch (_) {
      // already read
    }
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body ?? {'error': {'message': message}}));
    await r.response.close();
  }

  /// The body of [r]: at most [most] bytes, all arrived within [within]. Null with the status to answer (413 too
  /// large, 408 too slow) otherwise; the connection is then closed, its body unread.
  Future<(Uint8List?, int)> _body(HttpRequest r, int most, Duration within) async {
    if (r.contentLength > most) return (null, 413);
    final out = BytesBuilder(copy: false);
    final done = Completer<(Uint8List?, int)>();
    late final StreamSubscription<List<int>> sub;
    final timer = Timer(within, () {
      if (done.isCompleted) return;
      done.complete((null, 408));
      unawaited(sub.cancel().catchError((Object _) {}));
    });
    sub = r.listen((chunk) {
      if (done.isCompleted) return;
      out.add(chunk);
      if (out.length > most) {
        done.complete((null, 413));
        unawaited(sub.cancel().catchError((Object _) {}));
      }
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete((null, 400));
    }, onDone: () {
      if (!done.isCompleted) done.complete((out.takeBytes(), 200));
    }, cancelOnError: true);
    try {
      return await done.future;
    } finally {
      timer.cancel();
    }
  }

  /// The body of [r] as JSON (see [_body]); null with the status to answer when it is too large, too slow or not JSON.
  Future<(Object?, int)> _json(HttpRequest r, int most, Duration within) async {
    final (bytes, status) = await _body(r, most, within);
    if (bytes == null) return (null, status);
    try {
      return (jsonDecode(utf8.decode(bytes)), 200);
    } on FormatException {
      return (null, 400);
    }
  }

  Future<void> _refusedBody(HttpRequest r, int status) => status == 408
      ? _say(r, 408, 'the request took too long to arrive')
      : status == 413 ? _say(r, 413, 'the request is too large') : _say(r, 400, 'the request could not be read');

  Future<void> _pairStart(HttpRequest r, String from) async {
    if (!_pairStarts.take(from)) return _refuse(r, 429, 'too many tries; wait a minute');
    final (bytes, status) = await _body(r, limits.smallBody, limits.smallBodyTime);
    if (bytes == null) return _refusedBody(r, status);
    if (devices.full) return _say(r, 403, 'this server already serves $maxDevices devices; unpair one first');
    final (nonce, why) = pairing.start(from);
    if (nonce == null) {
      return switch (why) {
        PairRefused.busy => _say(r, 503, 'pairing is busy just now; try again in a minute'),
        PairRefused.tooMany => _say(r, 429, 'too many pairing tries from here; run "solace-home pair" again'),
        _ => _say(r, 403, 'pairing is not open: run "solace-home pair" on the server'),
      };
    }
    await _say(r, 200, '', {'protocol': homeProtocol, 'server_nonce': nonce});
  }

  Future<void> _pairFinish(HttpRequest r, String from) async {
    final (j, status) = await _json(r, limits.smallBody, limits.smallBodyTime);
    if (status == 408 || status == 413) return _refusedBody(r, status);
    if (j is! Map || j['protocol'] != homeProtocol) {
      _failures.take(from);
      return _say(r, 400, 'not a pairing request this server reads');
    }
    final ns = j['server_nonce'], np = j['phone_nonce'], name = j['name'], proof = j['proof'];
    if (ns is! String || np is! String || name is! String || proof is! String || devices.full) {
      _failures.take(from);
      return _say(r, 400, 'not a pairing request this server reads');
    }
    final (ok, why) = pairing.check(serverNonce: ns, phoneNonce: np, name: name, proof: proof,
        fingerprint: fingerprint, from: from);
    if (ok == null) {
      _failures.take(from);
      return why == PairRefused.tooMany
          ? _say(r, 429, 'too many pairing tries from here; run "solace-home pair" again')
          : _say(r, 403, 'the code was not right, or pairing is not open');
    }
    final (device, token) = await devices.add(name, _random);
    final serverProof = pairProof(ok.code, 'server', fingerprint: fingerprint, serverNonce: ns, phoneNonce: np,
        deviceId: device.id, tokenSha: tokenHash(token));
    await _say(r, 200, '', {'protocol': homeProtocol, 'device_id': device.id, 'token': token, 'proof': serverProof,
        'model': model.toJson()});
    unawaited(onDevicesChanged?.call());
  }

  Future<void> _status(HttpRequest r, PairedDevice d) async {
    final (bytes, status) = await _body(r, limits.smallBody, limits.smallBodyTime);
    if (bytes == null) return _refusedBody(r, status);
    r.response.headers.set(servedModelHeader, model.sha256);
    await _say(r, 200, '', {'protocol': homeProtocol, 'ready': upstream.ready, 'model': model.toJson(),
        'device': {'id': d.id, 'name': d.name}, 'devices': devices.devices.length, 'engine': 'llama.cpp b11669'});
  }

  Future<void> _unpair(HttpRequest r, PairedDevice d) async {
    final (bytes, status) = await _body(r, limits.smallBody, limits.smallBodyTime);
    if (bytes == null) return _refusedBody(r, status);
    _active.remove(d.id)?.stop();
    await devices.remove(d.id);
    await _say(r, 200, '', {'unpaired': true});
    unawaited(onDevicesChanged?.call());
  }

  Future<void> _chat(HttpRequest r, PairedDevice d) async {
    final (j, status) = await _json(r, limits.chatBody, limits.chatBodyTime);
    if (j == null) {
      return status == 400 ? _say(r, 413, 'the request is too large or not JSON') : _refusedBody(r, status);
    }
    final (req, why) = ChatRequest.from(j);
    if (req == null) return _say(r, 400, 'refused: $why');
    final slot = devices.slotOf(d);
    if (slot < 0) return _say(r, 401, 'not paired');
    // a newer request from the same device replaces the one before (the phone let it go, or lost its connection)
    _active.remove(d.id)?.stop();
    final UpstreamReply reply;
    try {
      reply = await upstream.chat(req, slot);
    } on UpstreamDown {
      return _say(r, 503, 'the model is starting or restarting; try again in a minute');
    } on UpstreamFailed catch (e) {
      return _say(r, e.status == 400 ? 400 : 502, 'the model could not answer this request');
    }
    final running = _active[d.id] = _Running(reply);
    final res = r.response
      ..statusCode = 200
      ..bufferOutput = false
      ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.set(servedModelHeader, model.sha256);

    // One writer for the whole response (H19-03): every event, the pings included, goes through one queue, so a
    // ping never writes while a word's flush is still pending (which threw, and cut the reply as if the phone had
    // gone). A ping is sent only when nothing is being written and nothing went out for a ping's interval.
    var gone = false, writing = 0;
    var lastOut = DateTime.now();
    var queue = Future<void>.value();
    Future<void> send(String event) {
      if (gone) return queue;
      writing++;
      return queue = queue.then((_) async {
        try {
          if (gone) return;
          res.write(event);
          await res.flush();
          lastOut = DateTime.now();
        } catch (_) {
          gone = true; // the phone went away: nothing more can reach it
          reply.abort();
        } finally {
          writing--;
        }
      });
    }

    // the connection failing under a write is also seen here (the web server keeps a socket error to itself)
    unawaited(res.done.then((_) {}, onError: (Object _) {
      gone = true;
      reply.abort();
    }));
    final ping = Timer.periodic(limits.ping, (_) {
      if (gone || writing > 0 || DateTime.now().difference(lastOut) < limits.ping) return;
      unawaited(send(': ping\n\n'));
    });
    try {
      await for (final piece in reply.pieces) {
        if (running.stopped) break;
        await send('data: ${jsonEncode({'choices': [{'index': 0, 'delta': {'content': piece}, 'finish_reason': null}]})}\n\n');
        if (gone) break;
      }
      // stopped here (a newer request from the device, or it was unpaired): an end without [DONE], said as such
      if (running.stopped) throw const UpstreamFailed(499);
      if (!gone) {
        await send('data: ${jsonEncode({'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]})}\n\n');
        await send('data: [DONE]\n\n');
      }
    } catch (_) {
      // the model failed or stopped before its end: said in so many words, never a [DONE]
      await send('data: ${jsonEncode({'error': {'message': 'the model stopped before the reply was finished'}})}\n\n');
    } finally {
      ping.cancel();
      await queue;
      if (identical(_active[d.id], running)) _active.remove(d.id);
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

/// A generation the gateway may stop: once [stop]ped, its reply ends with an error event, never [DONE].
class _Running {
  _Running(this.reply);
  final UpstreamReply reply;
  bool stopped = false;

  void stop() {
    stopped = true;
    reply.abort();
  }
}
