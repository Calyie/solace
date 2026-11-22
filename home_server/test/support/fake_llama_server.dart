// A stand-in for llama-server in the tests (no model): it listens where --host says (a Unix socket path, as the
// gateway starts it), answers /health, says its core limit at /limits (read from /proc on Linux), and streams a short
// reply to /v1/chat/completions for requests carrying the key from LLAMA_API_KEY. Started by a shell script that the
// tests write, through the gateway's own command line (llama.dart llamaCommand).
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final host = args[args.indexOf('--host') + 1];
  final np = args[args.indexOf('-np') + 1];
  final key = Platform.environment['LLAMA_API_KEY'];
  final server = await HttpServer.bind(InternetAddress(host, type: InternetAddressType.unix), 0);
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    exit(0);
  });
  await for (final r in server) {
    final res = r.response;
    if (r.uri.path == '/health') {
      res.write('{"status":"ok"}');
    } else if (r.uri.path == '/limits') {
      final f = File('/proc/self/limits');
      res.write(f.existsSync() ? f.readAsLinesSync().firstWhere((l) => l.startsWith('Max core file size')) : 'none');
    } else if (r.headers.value('authorization') != 'Bearer $key') {
      res.statusCode = 401;
    } else if (r.uri.path == '/v1/chat/completions') {
      final j = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      res.headers.contentType = ContentType('text', 'event-stream');
      for (final w in ['slot ', '${j['id_slot']}', ' of $np']) {
        res.write('data: ${jsonEncode({'choices': [{'delta': {'content': w}}]})}\n\n');
      }
      res.write('data: [DONE]\n\n');
    } else {
      res.statusCode = 404;
    }
    await res.close();
  }
}
