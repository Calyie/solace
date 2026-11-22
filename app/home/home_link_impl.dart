// Solace Home's network code (docs/HOME_SERVER.md): compiled ONLY into the Home build, whose entry point is
// home/main_home.dart (built with --dart-define=SOLACE_HOME=true). Nothing in lib/ imports this folder, so the default,
// air-gapped build contains none of it (test/home/home_build_test.dart checks both).
//
// What it does:
// - the network guard of the Home build ([HomeGuard]): every web client the app could make reaches only the paired
//   home server's address and port, over TLS, and only when the server shows the certificate pinned at pairing;
//   anything else fails before a connection is made. The default guards (lib/core/network_guard.dart) stay in force
//   for sockets: the Home build adds no other way out;
// - pairing ([GatewayHomeLink.pair]): the one-time code is proved, never sent (home_protocol.dart);
// - the therapist model on the server ([HomeServerModel]): the reply streamed word by word, Stop honoured, the same
//   time limits as the model on the device (core/model_turns.dart), plain errors when the server cannot be reached,
//   and the model on this device answering instead when one is installed. A reply counts only when its stream ends
//   with [DONE] (H19-03); a silent link (no ping and no word for [HomeServerModel.silence]) is a dead one (H19-04);
//   everything read from the server is bounded in size (H19-07); and every reply must name the model that was checked
//   (H19-08).
// Only the conversation the model needs is sent, exactly what the model on the device would be given; the safety
// check, the voice, memory and every other piece of the person's data stay on the phone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:solace/core/home_link.dart';
import 'package:solace/core/llama_model.dart' show LlamaModelRuntime;
import 'package:solace/core/model.dart';
import 'package:solace/core/model_turns.dart';

import 'home_protocol.dart';

/// Where the Home build may connect: the paired server, and the certificate it must show (null only while pairing).
class HomeEndpoint {
  const HomeEndpoint(this.host, this.port, [this.fingerprint]);
  final String host;
  final int port;
  final String? fingerprint;
}

/// The certificate the server showed was not the one pinned at pairing.
class CertificateChanged implements Exception {
  const CertificateChanged();
}

/// The Home build's web-client guard: a client from here can reach [allowed] only.
class HomeGuard extends HttpOverrides {
  HomeGuard([this.allowed, this.lookup = _systemLookup]);
  HomeEndpoint? allowed;

  /// Looks a host name up (the tests give their own). Only an address on this computer's network or Tailscale is
  /// ever connected to, so a name or address on the open internet gets no connection and no TLS hello at all
  /// (review N-03, 2026-11-19); the address of the connection made is checked again once it is open.
  final Future<List<InternetAddress>> Function(String host) lookup;

  /// How long one of several addresses may take to connect before the next is tried (the client's own time limit,
  /// 10 seconds, still bounds the whole connection).
  static const perAddress = Duration(seconds: 4);

  static Future<List<InternetAddress>> _systemLookup(String host) =>
      InternetAddress.lookup(host).timeout(const Duration(seconds: 10));

  /// The addresses of [host] that are on this computer's network or Tailscale, in the order looked up.
  Future<List<InternetAddress>> _homeAddresses(String host) async {
    final literal = InternetAddress.tryParse(host);
    final home = [for (final a in literal != null ? [literal] : await lookup(host)) if (isLocalOrTailscale(a)) a];
    if (home.isEmpty) {
      throw const SocketException('Solace Home connects only on your own network or through Tailscale');
    }
    return home;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final a = allowed;
    if (a == null || a.fingerprint == null) {
      throw const SocketException('Solace Home: no home server is paired, so nothing may be reached');
    }
    return clientFor(a);
  }

  /// A client that reaches [e] only. While pairing ([e] has no fingerprint), any certificate is accepted and handed to
  /// [saw]: the pairing proofs bind it, and the phone pins it once the server's proof checks.
  HttpClient clientFor(HomeEndpoint e, {void Function(String fingerprint)? saw}) {
    final c = super.createHttpClient(SecurityContext(withTrustedRoots: false))
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15)
      ..autoUncompress = false
      ..badCertificateCallback = ((_, _, _) => false);
    c.connectionFactory = (uri, proxyHost, proxyPort) {
      // host names compared in lower case (H19-06): Dart's Uri lowers a name, the person may have typed capitals
      if (uri.scheme != 'https' || uri.host.toLowerCase() != e.host.toLowerCase() || uri.port != e.port ||
          proxyHost != null) {
        return Future.error(const SocketException('Solace Home reaches only the paired home server'));
      }
      String? shown;
      bool accept(X509Certificate cert) {
        final fp = certificateFingerprint(cert.der);
        shown = fp;
        saw?.call(fp);
        return e.fingerprint == null || sameText(fp, e.fingerprint!);
      }

      // no trusted roots at all, so every certificate goes through [accept]; checked again on the open connection.
      // Only the name's home or Tailscale addresses are tried, one after another as an ordinary connect would; a
      // certificate or TLS failure ends the attempt at once.
      return _homeAddresses(e.host).then((addresses) {
        ConnectionTask<SecureSocket>? current;
        var cancelled = false;
        Future<Socket> attempt(int i) async {
          final last = i + 1 >= addresses.length;
          final task = await SecureSocket.startConnect(addresses[i], e.port,
              context: SecurityContext(withTrustedRoots: false), onBadCertificate: accept);
          current = task;
          if (cancelled) task.cancel();
          try {
            // an address that never answers is left after [perAddress] when another remains (review R2-05); a
            // connection it makes later is closed at once
            final s = await (last
                ? task.socket
                : task.socket.timeout(perAddress, onTimeout: () {
                    task.cancel();
                    unawaited(task.socket.then((late) => late.destroy(), onError: (Object _) {}));
                    throw const SocketException('Solace Home: no answer from this address');
                  }));
            // the client gave up (its time limit, or Stop) while the handshake ran: closed, never left open (R2-04)
            if (cancelled) {
              s.destroy();
              throw const SocketException('Solace Home: the connection was cancelled');
            }
            // only this computer's network or Tailscale, never the open internet (owner, 2026-11-19), checked again
            // on the connection made, before a single request is sent
            if (!isLocalOrTailscale(s.remoteAddress)) {
              s.destroy();
              throw const SocketException('Solace Home connects only on your own network or through Tailscale');
            }
            final peer = s.peerCertificate;
            if (peer == null || !accept(peer)) {
              s.destroy();
              throw const CertificateChanged();
            }
            return s;
          } catch (err) {
            if (shown != null && e.fingerprint != null && !sameText(shown!, e.fingerprint!)) {
              throw const CertificateChanged();
            }
            if (err is CertificateChanged || err is TlsException || cancelled || i + 1 >= addresses.length) rethrow;
            return attempt(i + 1);
          }
        }

        return ConnectionTask.fromSocket<Socket>(attempt(0), () {
          cancelled = true;
          current?.cancel();
        });
      });
    };
    return c;
  }
}

/// "192.168.1.20:8443", "[fd7a::1]:8443", "100.101.102.103" (port 8443) or a name; null when it cannot be read. The
/// host comes back in lower case (H19-06).
(String, int)? readAddress(String typed) {
  var s = typed.trim();
  for (final scheme in ['https:', 'http:']) {
    if (s.toLowerCase().startsWith(scheme)) s = s.substring(scheme.length).replaceFirst(RegExp('^/+'), '');
  }
  s = s.replaceFirst(RegExp(r'/+$'), '');
  if (s.isEmpty || s.length > 255 || s.contains(RegExp(r'[\s/@?#]'))) return null;
  String host;
  var port = 8443;
  final v6 = RegExp(r'^\[([0-9a-fA-F:.]+)\](?::(\d{1,5}))?$').firstMatch(s);
  if (v6 != null) {
    host = v6.group(1)!;
    if (v6.group(2) != null) port = int.parse(v6.group(2)!);
  } else {
    final parts = s.split(':');
    if (parts.length > 2) return null;
    host = parts.first;
    if (parts.length == 2) {
      final p = int.tryParse(parts[1]);
      if (p == null) return null;
      port = p;
    }
    if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) return null;
  }
  if (port < 1 || port > 65535) return null;
  return (host.toLowerCase(), port);
}

HomeModelInfo? _modelFrom(Object? j) {
  if (j is! Map) return null;
  final sha = j['sha256'], name = j['name'], size = j['size'], tier = j['tier'];
  if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) || name is! String || size is! int) return null;
  return HomeModelInfo(sha256: sha, name: name.length > 255 ? name.substring(0, 255) : name, size: size,
      light: tier == 'light');
}

class GatewayHomeLink implements HomeLink {
  GatewayHomeLink({HomeGuard? guard, Random? random})
      : guard = guard ?? HomeGuard(),
        _random = random ?? Random.secure();
  final HomeGuard guard;
  final Random _random;

  @override
  void allowOnly(HomePairing? p) {
    guard.allowed = p == null ? null : HomeEndpoint(p.host, p.port, p.certSha256);
    HttpOverrides.global = guard;
  }

  HttpClient _pinned(HomePairing p) => guard.clientFor(HomeEndpoint(p.host, p.port, p.certSha256));

  /// The most the phone reads of any answer but a reply (H19-07): pairing, status and unpair answers are a few
  /// hundred bytes.
  static const mostAnswer = 65536;

  static Future<(int, Object?)> _send(HttpClient c, String method, String host, int port, String path,
      {String? token, Object? body, Duration timeout = const Duration(seconds: 20)}) async {
    final req = await c.openUrl(method, Uri(scheme: 'https', host: host, port: port, path: path)).timeout(timeout);
    if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout);
    // counted while it is read, and never past the limit: the first pairing step is not yet pinned, so anything in
    // the middle could otherwise send an endless answer
    final bytes = await readAtMost(res, mostAnswer).timeout(timeout);
    if (bytes == null) return (res.statusCode, null);
    try {
      return (res.statusCode, jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      return (res.statusCode, null);
    }
  }

  /// The bytes of [s], or null as soon as they pass [most] (the rest is not read).
  static Future<Uint8List?> readAtMost(Stream<List<int>> s, int most) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in s) {
      out.add(chunk);
      if (out.length > most) return null;
    }
    return out.takeBytes();
  }

  static HomeLinkError _reach(Object e) => e is CertificateChanged ? HomeLinkError.certificateChanged
      : e is HandshakeException ? HomeLinkError.notSolace : HomeLinkError.unreachable;

  @override
  Future<(HomePairing, HomeModelInfo)> pair(String address, String code, String deviceName) async {
    final at = readAddress(address);
    if (at == null) throw HomeLinkError.badAddress;
    final typed = readCode(code);
    if (typed == null) throw HomeLinkError.badCode;
    final (host, port) = at;
    String? fp;
    final first = guard.clientFor(HomeEndpoint(host, port), saw: (f) => fp ??= f);
    final String ns;
    try {
      final (status, j) = await _send(first, 'POST', host, port, pairStartPath, body: const {});
      if (status == 403) throw HomeLinkError.pairingClosed;
      if (status == 429) throw HomeLinkError.tooManyTries;
      if (status == 503) throw HomeLinkError.pairingBusy; // every nonce taken for the moment (H19-09)
      if (status != 200 || j is! Map || j['protocol'] != homeProtocol || j['server_nonce'] is! String) {
        throw HomeLinkError.notSolace;
      }
      ns = j['server_nonce'] as String;
    } on HomeLinkError {
      rethrow;
    } catch (e) {
      throw _reach(e);
    } finally {
      first.close(force: true);
    }
    final seen = fp;
    if (seen == null) throw HomeLinkError.notSolace;
    // the rest only with the certificate seen just now
    final pinned = guard.clientFor(HomeEndpoint(host, port, seen));
    try {
      final np = randomText(_random, 32);
      final proof = pairProof(typed, 'phone', fingerprint: seen, serverNonce: ns, phoneNonce: np);
      final (status, j) = await _send(pinned, 'POST', host, port, pairFinishPath, body: {
        'protocol': homeProtocol, 'server_nonce': ns, 'phone_nonce': np, 'name': deviceName, 'proof': proof,
      });
      if (status == 403) throw HomeLinkError.wrongCode;
      if (status == 429) throw HomeLinkError.tooManyTries;
      if (status != 200 || j is! Map) throw HomeLinkError.notSolace;
      final id = j['device_id'], token = j['token'], serverProof = j['proof'], model = _modelFrom(j['model']);
      if (id is! String || token is! String || serverProof is! String || model == null || token.length < 32 ||
          token.length > 128) {
        throw HomeLinkError.notSolace;
      }
      final expected = pairProof(typed, 'server', fingerprint: seen, serverNonce: ns, phoneNonce: np, deviceId: id,
          tokenSha: tokenHash(token));
      // a server that does not know the code (a machine in the middle) cannot make this proof
      if (!sameText(expected, serverProof)) throw HomeLinkError.notProved;
      final now = DateTime.now();
      return (HomePairing(host: host, port: port, certSha256: seen, token: token, deviceId: id,
          date: '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}'), model);
    } on HomeLinkError {
      rethrow;
    } catch (e) {
      throw _reach(e);
    } finally {
      pinned.close(force: true);
    }
  }

  @override
  Future<HomeModelInfo> status(HomePairing p) async {
    final c = _pinned(p);
    try {
      final (status, j) = await _send(c, 'GET', p.host, p.port, statusPath, token: p.token,
          timeout: const Duration(seconds: 10));
      if (status == 401) throw HomeLinkError.notPaired;
      if (status == 429) throw HomeLinkError.tooManyTries;
      final model = j is Map ? _modelFrom(j['model']) : null;
      if (status != 200 || model == null) throw HomeLinkError.notSolace;
      return model;
    } on HomeLinkError {
      rethrow;
    } catch (e) {
      throw _reach(e);
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<void> unpair(HomePairing p) async {
    final c = _pinned(p);
    try {
      final (status, _) = await _send(c, 'POST', p.host, p.port, unpairPath, token: p.token,
          timeout: const Duration(seconds: 10));
      if (status != 200 && status != 401) throw HomeLinkError.notSolace;
    } on HomeLinkError {
      rethrow;
    } catch (e) {
      throw _reach(e);
    } finally {
      c.close(force: true);
    }
  }

  @override
  ModelRuntime runtime(HomePairing p, {required Future<String?> Function(HomeModelInfo model) trusts,
      Future<ModelRuntime?> Function()? fallback, void Function(String status)? report,
      void Function(HomeModelInfo? model)? onModel}) =>
      HomeServerModel(this, p, trusts: trusts, fallback: fallback, report: report, onModel: onModel);
}

/// The therapist model on the paired home server, with the model on this device as a fallback when one is installed.
class HomeServerModel implements ModelRuntime, PromptPreparer, ReplyCanceller, ReleasableRuntime, WritesElsewhere {
  HomeServerModel(this.link, this.pairing, {required this.trusts, this.fallback, this.report, this.onModel,
      this.limits = GenerationLimits.standard, this.silence = const Duration(seconds: 20)});
  final GatewayHomeLink link;
  final HomePairing pairing;

  /// Why the phone will not use the served model (its own lists, as for a model on the device), or null.
  final Future<String?> Function(HomeModelInfo model) trusts;

  /// Loads the model on this device, when one is installed (once, the first time the server cannot answer).
  final Future<ModelRuntime?> Function()? fallback;
  final void Function(String status)? report;
  final void Function(HomeModelInfo? model)? onModel;
  final GenerationLimits limits;

  /// No ping and no word from the server for this long is a dead link (H19-04): the server pings every 5 seconds
  /// while its model reads, so this is four missed pings. A link that dies without a reset (the phone left the
  /// Wi-Fi, a router forgot the connection) used to leave the reply waiting for minutes.
  final Duration silence;

  /// The longest line, and the most characters a reply may have for each token asked (H19-07): a paired server
  /// sending more is stopped there.
  static const mostLine = 65536, charsPerToken = 32;

  final _turns = ModelTurns();
  HttpClient? _client; // the request being written now, closed by Stop
  HomeModelInfo? _checked;
  ModelRuntime? _local; // the model on this device, once loaded as the fallback
  ModelRuntime? _localNow;
  DateTime? _downUntil; // after the server could not be reached, the model on this device answers for a minute
  bool _lastOnServer = true;

  @override
  bool get writesOnServer => !_down || _local == null;

  @override
  bool get lastOnServer => _lastOnServer;

  /// Lets go of the link and of the model on this device it fell back to (Unpair, Delete everything).
  @override
  Future<void> release() async {
    _turns.cancelRunning();
    _client?.close(force: true);
    final l = _local;
    _local = null;
    if (l is LlamaModelRuntime) await l.dispose();
    if (l is ReleasableRuntime) await (l as ReleasableRuntime).release();
  }

  @override
  String get name => 'Home server (${_checked?.name ?? 'model'} on ${pairing.host})';

  bool get _down {
    final d = _downUntil;
    return d != null && DateTime.now().isBefore(d);
  }

  /// Reads the conversation's start ahead (check-in). Not while the server could not be reached a moment ago, and a
  /// server that cannot be reached now marks it so, so the reply that follows does not wait for it again (H19-04).
  @override
  Future<void> prepare(List<Map<String, String>> messages) {
    if (_down) return Future<void>.value();
    return _turns.run(() => _readAhead(messages), cancel: _cancel, maxTokens: 1, limits: limits)
        .drain<void>().catchError((Object _) {}); // never the fallback, just to read ahead
  }

  Stream<String> _readAhead(List<Map<String, String>> messages) async* {
    try {
      // await for, not yield*: an error of a stream given to yield* is passed on, never caught here
      await for (final w in _fromServer(messages, 1)) {
        yield w;
      }
    } on HomeLinkError catch (e) {
      if (e == HomeLinkError.unreachable) _downUntil = DateTime.now().add(const Duration(minutes: 1));
    }
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) =>
      _turns.run(() => _withFallback(messages, maxTokens), cancel: _cancel, maxTokens: maxTokens, limits: limits);

  @override
  void cancelReply() => _turns.cancelRunning();

  void _cancel() {
    _client?.close(force: true); // the server sees the connection go and stops the model at once
    _client = null;
    final l = _localNow;
    if (l is ReplyCanceller) (l as ReplyCanceller).cancelReply();
  }

  Stream<String> _withFallback(List<Map<String, String>> messages, int maxTokens) async* {
    if (_down) {
      // the server could not be reached a moment ago: no wait before each reply meanwhile when this device has a
      // model of its own (loaded now if it was not yet); without one the server is tried again
      final local0 = _local ??= await _loadLocal();
      if (local0 != null) {
        _localNow = local0;
        _lastOnServer = false;
        try {
          yield* local0.generate(messages, maxTokens: maxTokens);
        } finally {
          _localNow = null;
        }
        return;
      }
    }
    var any = false;
    try {
      await for (final piece in _fromServer(messages, maxTokens)) {
        any = true;
        _lastOnServer = true;
        yield piece;
      }
      return;
    } on HomeLinkError catch (e) {
      if (e == HomeLinkError.unreachable || e == HomeLinkError.lostMidReply) {
        _downUntil = DateTime.now().add(const Duration(minutes: 1));
      }
      // words already shown are never replaced by another model's; only a request that got no word falls back
      if (any || e == HomeLinkError.stopped) rethrow;
      final local = _local ??= await _loadLocal();
      if (local == null) rethrow;
      report?.call('${e.sayToPerson} The model on this device answers for now.');
      _localNow = local;
      _lastOnServer = false;
      try {
        yield* local.generate(messages, maxTokens: maxTokens);
      } finally {
        _localNow = null;
      }
    }
  }

  /// The model on this device, loaded the first time the server cannot answer (and tried again next time if it could
  /// not be loaded); null when none is installed.
  Future<ModelRuntime?> _loadLocal() async {
    try {
      return await fallback?.call();
    } catch (_) {
      return null;
    }
  }

  Stream<String> _fromServer(List<Map<String, String>> messages, int maxTokens) async* {
    for (var attempt = 0;; attempt++) {
      if (_checked == null) {
        final model = await link.status(pairing);
        final why = await trusts(model);
        if (why != null) {
          onModel?.call(null);
          throw HomeLinkError.modelNotTrusted(why);
        }
        _checked = model;
        onModel?.call(model);
      }
      final c = link._pinned(pairing);
      _client = c;
      try {
        final HttpClientResponse res;
        try {
          final req = await c.postUrl(Uri(scheme: 'https', host: pairing.host, port: pairing.port, path: chatPath));
          req.headers
            ..set(HttpHeaders.authorizationHeader, 'Bearer ${pairing.token}')
            ..contentType = ContentType.json;
          req.write(jsonEncode(ChatRequest(messages, maxTokens).toJson()));
          res = await req.close().timeout(silence); // the gateway answers its headers at once
        } catch (e) {
          if (!identical(_client, c)) throw HomeLinkError.stopped;
          _checked = null; // looked at again once it can be reached
          throw e is TimeoutException ? HomeLinkError.unreachable : GatewayHomeLink._reach(e);
        }
        if (res.statusCode != 200) {
          await GatewayHomeLink.readAtMost(res, GatewayHomeLink.mostAnswer).timeout(const Duration(seconds: 5))
              .catchError((Object _) => null);
          if (res.statusCode == 503) _checked = null; // restarting: looked at again, as the model may change
          throw switch (res.statusCode) {
            401 => HomeLinkError.notPaired,
            429 => HomeLinkError.tooManyTries,
            503 => HomeLinkError.starting,
            _ => HomeLinkError.notSolace,
          };
        }
        // H19-08: every reply names the model that writes it; another than the one checked is looked at again (once)
        if (res.headers.value(servedModelHeader) != _checked?.sha256) {
          _checked = null;
          if (attempt == 0) continue;
          throw HomeLinkError.notSolace;
        }
        var any = false, chars = 0;
        final most = maxTokens * charsPerToken + 256;
        try {
          final lines = boundedLines(res.timeout(silence, onTimeout: (sink) {
            sink
              ..addError(const _Silent())
              ..close();
          }), mostLine);
          await for (final line in lines) {
            if (!line.startsWith('data:')) continue; // comments (the server's pings) and blank lines
            final data = line.substring(5).trim();
            if (data == '[DONE]') return;
            final Object? j;
            try {
              j = jsonDecode(data);
            } on FormatException {
              continue;
            }
            if (j is! Map) continue;
            if (j['error'] != null) throw HomeLinkError.stoppedOnServer;
            final choices = j['choices'];
            if (choices is! List || choices.isEmpty || choices.first is! Map) continue;
            final delta = (choices.first as Map)['delta'];
            final content = delta is Map ? delta['content'] : null;
            if (content is String && content.isNotEmpty) {
              chars += content.length;
              if (chars > most) throw HomeLinkError.stoppedOnServer; // far more than the reply asked for
              any = true;
              yield content;
            }
          }
          // H19-03: the stream ended without [DONE]: what came is not the whole reply, and is never kept as one
          if (!identical(_client, c)) throw HomeLinkError.stopped;
          throw HomeLinkError.cutOff;
        } on HomeLinkError {
          rethrow;
        } on _Silent {
          // H19-04: no ping and no word for [silence]: the link is dead
          if (!identical(_client, c)) throw HomeLinkError.stopped;
          _checked = null;
          throw any ? HomeLinkError.lostMidReply : HomeLinkError.unreachable;
        } on LineTooLong {
          throw HomeLinkError.stoppedOnServer;
        } catch (_) {
          if (!identical(_client, c)) throw HomeLinkError.stopped;
          _checked = null;
          throw HomeLinkError.lostMidReply;
        }
      } finally {
        if (identical(_client, c)) _client = null;
        c.close(force: true);
      }
    }
  }
}

/// No byte from the server for [HomeServerModel.silence].
class _Silent implements Exception {
  const _Silent();
}
