// The server's own controls: `solace-home pair`, `devices`, `unpair` and `status` talk to the running gateway through
// a Unix socket in its private folder (mode 700), so only the same user on the same computer can open a pairing window
// or remove a device. Nothing here is reachable from the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';

typedef AdminHandler = Future<Map<String, Object?>> Function(String command, List<String> args);

class AdminSocket {
  AdminSocket(this.path, this.handle);
  final String path;
  final AdminHandler handle;
  ServerSocket? _server;

  Future<void> start() async {
    final f = File(path);
    if (await f.exists()) await f.delete(); // left by a gateway that did not stop cleanly
    final server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
    try {
      await makePrivate(path, 0x180); // checked (H19-18): an open control socket would let anyone pair or unpair
    } catch (_) {
      await server.close();
      rethrow;
    }
    _server = server;
    server.listen((s) => unawaited(_serve(s)), onError: (Object _) {});
  }

  Future<void> _serve(Socket s) async {
    try {
      final line = await utf8.decoder.bind(s).transform(const LineSplitter()).first
          .timeout(const Duration(seconds: 5));
      if (line.length > 1000) throw const FormatException();
      final j = jsonDecode(line);
      if (j is! Map || j['command'] is! String) throw const FormatException();
      final args = [for (final a in (j['args'] is List ? j['args'] as List : const [])) '$a'];
      s.write('${jsonEncode(await handle(j['command'] as String, args))}\n');
    } catch (_) {
      s.write('${jsonEncode({'error': 'not understood'})}\n');
    } finally {
      await s.flush().catchError((Object _) {});
      await s.close().catchError((Object _) {});
    }
  }

  Future<void> stop() async {
    await _server?.close();
    try {
      await File(path).delete();
    } catch (_) {}
  }
}

/// Sends [command] to the running gateway at [path] and returns its answer.
Future<Map<String, Object?>> askGateway(String path, String command, [List<String> args = const []]) async {
  final Socket s;
  try {
    s = await Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);
  } on SocketException {
    throw StateError('Solace Home is not running here (start it with: solace-home serve)');
  }
  try {
    s.write('${jsonEncode({'command': command, 'args': args})}\n');
    await s.flush();
    final line = await utf8.decoder.bind(s).transform(const LineSplitter()).first.timeout(const Duration(seconds: 10));
    final j = jsonDecode(line);
    return j is Map ? Map<String, Object?>.from(j) : {'error': 'not understood'};
  } on TimeoutException {
    return {'error': 'Solace Home did not answer in time. Try again in a moment.'};
  } catch (_) {
    return {'error': 'Solace Home did not answer. Try again in a moment.'};
  } finally {
    s.destroy();
  }
}
