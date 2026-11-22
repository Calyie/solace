// The gateway's listening socket (H19-02). Dart's own TLS server has no time limit on a handshake and no way to close
// a connection whose handshake never finishes, so connections are accepted here as plain TCP, counted, and given a
// deadline before anything else:
// - at most [ListenerLimits.connections] connections at once, and [ListenerLimits.perAddress] from one address (an
//   address counts as in [sourceOf]); any more are closed at once;
// - the TLS handshake must finish within [ListenerLimits.handshake], or the connection is closed;
// - a finished handshake is handed to the web server as a [Socket] ([_TlsSocket]), which gives the connection back to
//   the count when it closes. The web server's idle timeout then bounds how long a connection may take to send a
//   request's headers (gateway.dart).
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../../app/home/home_protocol.dart' show inTailscaleRange, ipv4Of, isLocalOrTailscale;
import 'dart:typed_data';

class ListenerLimits {
  const ListenerLimits({this.connections = 128, this.perAddress = 16, this.handshake = const Duration(seconds: 5)});
  final int connections, perAddress;
  final Duration handshake;
}

/// The key one source is counted under: its IPv4 address (an IPv4-mapped IPv6 address counts as the IPv4 address it
/// carries), or its full IPv6 address. Every IPv6 address let in is on this network (link-local or unique local, see
/// [admitted]), where one address is one device; counting them by /64, as on the internet, lumped every device of the
/// network into one count, so one device could lock the others out (review N-04, 2026-11-19).
String sourceOf(InternetAddress? a) {
  if (a == null) return '?';
  final v4 = ipv4Of(a);
  if (v4 != null) return v4.join('.');
  if (a.type == InternetAddressType.IPv6) return InternetAddress.fromRawAddress(a.rawAddress).address; // no zone id
  return a.address;
}

/// Whether a connection from [remote] is let in: only from this computer, its own network or Tailscale (see
/// isLocalOrTailscale). A peer in 100.64.0.0/10 counts as Tailscale only when [onTailnet], that is when this computer
/// is on a tailnet itself: on a rented or provider network that range can be the provider's, shared with its other
/// customers (review N-01, 2026-11-19).
bool admitted(InternetAddress? remote, {required bool onTailnet}) =>
    isLocalOrTailscale(remote) && (!inTailscaleRange(remote) || onTailnet);

/// Whether [a] is an any-address (0.0.0.0 or ::).
bool _isAny(InternetAddress a) => a.rawAddress.every((b) => b == 0);

/// Whether one of this computer's network interfaces has an address in 100.64.0.0/10, its Tailscale address.
Future<bool> hasTailscaleAddress() async {
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      if (i.addresses.any(inTailscaleRange)) return true;
    }
  } catch (_) {}
  return false;
}

class GuardedListener extends Stream<Socket> implements ServerSocket {
  GuardedListener._(this._tcp, this._context, this.limits, this._admit, this._tailnetCheck);

  /// [admit] replaces the whole address rule (the tests); [tailnetCheck] answers whether this computer has a
  /// Tailscale address (the tests give their own; by default [hasTailscaleAddress]).
  static Future<GuardedListener> bind(Object address, int port, SecurityContext context,
      {ListenerLimits limits = const ListenerLimits(),
      bool Function(InternetAddress? remote)? admit,
      Future<bool> Function() tailnetCheck = hasTailscaleAddress}) async {
    final l = GuardedListener._(await RawServerSocket.bind(address, port), context, limits, admit, tailnetCheck);
    l._sub = l._tcp.listen(l._accept, onError: (Object _) {}, onDone: () {
      if (!l._out.isClosed) unawaited(l._out.close());
    });
    return l;
  }

  final RawServerSocket _tcp;
  final SecurityContext _context;
  final ListenerLimits limits;
  final bool Function(InternetAddress? remote)? _admit;
  final Future<bool> Function() _tailnetCheck;
  final _out = StreamController<Socket>();
  final _byAddress = <String, int>{};
  final _handshaking = <RawSocket>{};
  late final StreamSubscription<RawSocket> _sub;
  int _open = 0;
  bool _closed = false;
  bool? _tailnet;
  DateTime _tailnetAt = DateTime(2000);

  /// Connections open now (handshaking or handed on), and from [source] (the tests).
  int get open => _open;
  int openFrom(String source) => _byAddress[source] ?? 0;

  /// Whether this computer is on a tailnet, so a 100.64.0.0/10 peer may be Tailscale. Dart gives an accepted socket
  /// the listener's own address, not the one the connection arrived on (review R2-01, 2026-11-19), so: a listener on
  /// one address is on a tailnet when that address is a Tailscale address; a listener on every address asks this
  /// computer's network interfaces (kept 30 seconds when yes, 2 seconds when no, so Tailscale started after the
  /// gateway is noticed at once).
  Future<bool> onTailnet() async {
    final bound = _tcp.address;
    if (!_isAny(bound)) return inTailscaleRange(bound);
    final known = _tailnet, now = DateTime.now();
    if (known != null && now.difference(_tailnetAt) < Duration(seconds: known ? 30 : 2)) return known;
    _tailnetAt = now;
    return _tailnet = await _tailnetCheck();
  }

  void _accept(RawSocket raw) {
    final InternetAddress remote;
    try {
      remote = raw.remoteAddress;
    } catch (_) {
      raw.close();
      return;
    }
    final custom = _admit;
    if (custom != null) {
      custom(remote) ? _take(raw, remote) : raw.close();
      return;
    }
    // not this computer, the home network or Tailscale: closed at once, never answered, before TLS
    if (!isLocalOrTailscale(remote)) {
      raw.close();
      return;
    }
    if (!inTailscaleRange(remote)) {
      _take(raw, remote);
      return;
    }
    onTailnet().then((yes) => yes ? _take(raw, remote) : raw.close(), onError: (Object _) => raw.close());
  }

  void _take(RawSocket raw, InternetAddress remote) {
    final from = sourceOf(remote);
    if (_closed || _open >= limits.connections || (_byAddress[from] ?? 0) >= limits.perAddress) {
      raw.close();
      return;
    }
    _open++;
    _byAddress[from] = (_byAddress[from] ?? 0) + 1;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _open--;
      final n = (_byAddress[from] ?? 1) - 1;
      n <= 0 ? _byAddress.remove(from) : _byAddress[from] = n;
    }

    _handshaking.add(raw);
    var late = false;
    final deadline = Timer(limits.handshake, () {
      late = true;
      _handshaking.remove(raw);
      raw.close(); // the handshake in progress fails with it
      release();
    });
    RawSecureSocket.secureServer(raw, _context).then((secure) {
      deadline.cancel();
      _handshaking.remove(raw);
      if (late || _closed) {
        secure.close();
        release();
        return;
      }
      _out.add(_TlsSocket(secure, release));
    }, onError: (Object _) {
      deadline.cancel();
      _handshaking.remove(raw);
      try {
        raw.close();
      } catch (_) {}
      release();
    });
  }

  @override
  StreamSubscription<Socket> listen(void Function(Socket event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _out.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  int get port => _tcp.port;

  @override
  InternetAddress get address => _tcp.address;

  @override
  Future<ServerSocket> close() async {
    _closed = true;
    for (final raw in _handshaking.toList()) {
      raw.close();
    }
    _handshaking.clear();
    await _sub.cancel();
    await _tcp.close();
    if (!_out.isClosed) {
      final done = _out.close();
      if (_out.hasListener) await done; // with no listener the close would never be delivered, so never complete
    }
    return this;
  }
}

/// A finished TLS connection as the web server reads and writes it: a [Socket] over a [RawSecureSocket], with the
/// same pacing as Dart's own (a write is done when the system has taken its bytes; reading stops while the reader is
/// paused). It never throws at the web server for a connection that went away: writes after that are dropped and
/// flush reports the error. [_released] is called once, when it closes.
class _TlsSocket extends Stream<Uint8List> implements Socket {
  _TlsSocket(this._raw, this._released)
      : _local = _raw.address,
        _remote = _raw.remoteAddress,
        _localPort = _raw.port,
        _remotePort = _raw.remotePort {
    _raw.readEventsEnabled = false;
    _raw.writeEventsEnabled = false;
    _rawSub = _raw.listen(_onEvent, onError: (Object e) => _end(e), onDone: _end);
  }

  final RawSecureSocket _raw;
  final void Function() _released;
  final InternetAddress _local, _remote;
  final int _localPort, _remotePort;
  late final StreamSubscription<RawSocketEvent> _rawSub;
  late final StreamController<Uint8List> _in = StreamController<Uint8List>(
      onListen: _readMore, onPause: () => _reads(false), onResume: _readMore, onCancel: () => _reads(false));
  final _outQueue = ListQueue<Uint8List>();
  int _offset = 0;
  Completer<void>? _flushed;
  bool _ended = false;
  final _done = Completer<Socket>();

  @override
  Encoding encoding = utf8;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _in.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  void _reads(bool on) {
    if (_ended) return;
    try {
      _raw.readEventsEnabled = on;
    } catch (_) {}
  }

  void _readMore() {
    _reads(true);
    _drainReads();
  }

  void _drainReads() {
    while (!_ended && !_in.isClosed && _in.hasListener && !_in.isPaused) {
      final Uint8List? d;
      try {
        d = _raw.read();
      } catch (e) {
        _end(e);
        return;
      }
      if (d == null) break;
      _in.add(d);
    }
  }

  void _onEvent(RawSocketEvent e) {
    if (e == RawSocketEvent.read) {
      _drainReads();
    } else if (e == RawSocketEvent.write) {
      _pump();
    } else if (e == RawSocketEvent.readClosed) {
      _drainReads();
      if (!_in.isClosed) unawaited(_in.close());
    } else if (e == RawSocketEvent.closed) {
      _end();
    }
  }

  @override
  void add(List<int> data) {
    if (_ended || data.isEmpty) return;
    _outQueue.add(data is Uint8List ? data : Uint8List.fromList(data));
    _pump();
  }

  void _pump() {
    if (_ended) return;
    while (_outQueue.isNotEmpty) {
      final b = _outQueue.first;
      final int n;
      try {
        n = _raw.write(b, _offset, b.length - _offset);
      } catch (e) {
        _end(e);
        return;
      }
      _offset += n;
      if (_offset < b.length) {
        try {
          _raw.writeEventsEnabled = true;
        } catch (_) {}
        return;
      }
      _outQueue.removeFirst();
      _offset = 0;
    }
    final f = _flushed;
    _flushed = null;
    if (f != null && !f.isCompleted) f.complete();
  }

  @override
  Future flush() {
    if (_ended) return Future<void>.error(const SocketException('Solace Home: the connection is closed'));
    if (_outQueue.isEmpty) return Future<void>.value();
    return (_flushed ??= Completer<void>()).future;
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    // as a closed sink does: the web server's next write then throws, which is how the gateway sees a phone gone
    if (_ended) throw StateError('Solace Home: the connection is closed');
    final c = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = stream.listen((d) {
      if (_ended) {
        unawaited(sub.cancel());
        if (!c.isCompleted) c.completeError(const SocketException('Solace Home: the connection is closed'));
        return;
      }
      add(d);
      // the next piece only once the system has taken this one, as Dart's own sockets do
      if (_outQueue.isNotEmpty) sub.pause(flush().catchError((Object _) {}));
    }, onError: (Object e, StackTrace st) {
      if (!c.isCompleted) c.completeError(e, st);
    }, onDone: () {
      if (c.isCompleted) return;
      _ended ? c.completeError(const SocketException('Solace Home: the connection is closed')) : c.complete();
    }, cancelOnError: true);
    return c.future;
  }

  @override
  void write(Object? object) => add(encoding.encode('$object'));
  @override
  void writeln([Object? object = '']) => write('$object\n');
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) => write(objects.join(separator));
  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _end();

  @override
  Future close() async {
    try {
      await flush();
    } catch (_) {}
    _end();
    return this;
  }

  @override
  void destroy() => _end();

  void _end([Object? error]) {
    if (_ended) return;
    _ended = true;
    try {
      _raw.close();
    } catch (_) {}
    unawaited(_rawSub.cancel().catchError((Object _) {}));
    if (!_in.isClosed) {
      if (error != null && _in.hasListener) _in.addError(error);
      unawaited(_in.close().catchError((Object _) {}));
    }
    _outQueue.clear();
    final f = _flushed;
    _flushed = null;
    if (f != null && !f.isCompleted) {
      f.future.ignore(); // no one may be waiting: never an unhandled error
      f.completeError(const SocketException('Solace Home: the connection is closed'));
    }
    if (!_done.isCompleted) _done.complete(this);
    _released();
  }

  @override
  Future get done => _done.future;
  @override
  int get port => _localPort;
  @override
  int get remotePort => _remotePort;
  @override
  InternetAddress get address => _local;
  @override
  InternetAddress get remoteAddress => _remote;

  @override
  bool setOption(SocketOption option, bool enabled) {
    try {
      return _raw.setOption(option, enabled);
    } catch (_) {
      return false;
    }
  }

  @override
  Uint8List getRawOption(RawSocketOption option) => _raw.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _raw.setRawOption(option);
}
