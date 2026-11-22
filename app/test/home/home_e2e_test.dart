// Solace Home end to end on this computer (docs/HOME_SERVER.md): the real solace-home program, the real llama-server
// of build b11669 (the Linux CPU release) and a small model, with the app's own link (home/home_link_impl.dart) as the
// phone. Skipped unless pointed at them:
//
//   SOLACE_HOME_BIN=/path/to/solace-home              (dart compile exe home_server/bin/solace_home.dart)
//   SOLACE_LLAMA_SERVER=/path/to/llama-b11669/llama-server
//   SOLACE_E2E_MODEL=/path/to/SmolLM2-135M-Instruct-Q8_0.gguf    (any small GGUF; served with accept-unsigned)
//   flutter test test/home/home_e2e_test.dart
//
// It checks: setup, serve and pair through the program's own commands; pairing from the app with the code it printed;
// a reply streamed through the gateway; Stop; the server's folder holding only its certificate, key, device list and
// settings, with no word of the conversation; llama-server's command line (a Unix socket in the private folder and no
// TCP port at all, one slot per device, logs, slots endpoint, prompt cache and web page off), its environment (none of
// this computer's other variables) and its core limit (0, as the gateway's); unpairing; and the server stopping with
// its llama-server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/home_link.dart';

import '../../home/home_link_impl.dart';

final _env = Platform.environment;
final _bin = _env['SOLACE_HOME_BIN'], _llama = _env['SOLACE_LLAMA_SERVER'], _model = _env['SOLACE_E2E_MODEL'];

Future<int> _freePort() async {
  final s = await ServerSocket.bind('127.0.0.1', 0);
  final p = s.port;
  await s.close();
  return p;
}

String _sha256(String path) => (Process.runSync('sha256sum', [path]).stdout as String).split(' ').first;

void main() {
  final skip = _bin == null || _llama == null || _model == null
      ? 'set SOLACE_HOME_BIN, SOLACE_LLAMA_SERVER and SOLACE_E2E_MODEL to run' : null;

  test('a phone pairs with Solace Home and a real model answers through it, keeping nothing', () async {
    final tmp = await Directory.systemTemp.createTemp('solace_home_e2e');
    final home = '${tmp.path}/home', models = await Directory('${tmp.path}/models').create();
    final env = {'SOLACE_HOME_DIR': home, 'PATH': _env['PATH'] ?? '/usr/bin:/bin', 'HOME': _env['HOME'] ?? tmp.path,
        // a setting of this computer that would turn on slot files if it reached llama-server: it must not
        'LLAMA_ARG_SLOT_SAVE_PATH': '${tmp.path}/slots', 'SOLACE_E2E_SECRET': 'must-not-reach-llama'};
    // the model beside its .sha256 list, as on a phone
    final model0 = _model!, bin = _bin!, llama = _llama!;
    final name = model0.split('/').last;
    await Link('${models.path}/$name').create(model0);
    final sum = _sha256(model0);
    File('${models.path}/${name.replaceAll('.gguf', '.sha256')}').writeAsStringSync('$sum  $name\n');
    final port = await _freePort();
    final sock = '$home/llama.sock';
    Future<ProcessResult> run(List<String> args) =>
        Process.run(bin, args, environment: env, includeParentEnvironment: false);

    var r = await run(['setup', '--model', '${models.path}/$name', '--llama-server', llama, '--port', '$port',
        '--listen', '127.0.0.1', '--gpu-layers', '0', '--threads', '2']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    r = await run(['accept-unsigned', sum]);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final serve = await Process.start(bin, ['serve'], environment: env, includeParentEnvironment: false);
    final out = StringBuffer();
    final ready = Completer<void>();
    serve.stdout.transform(utf8.decoder).listen((s) {
      out.write(s);
      if (out.toString().contains('Solace Home is serving') && !ready.isCompleted) ready.complete();
    });
    serve.stderr.transform(utf8.decoder).listen(out.write);
    unawaited(serve.exitCode.then((c) {
      if (!ready.isCompleted) ready.completeError('solace-home serve stopped ($c): $out');
    }));
    try {
      await ready.future.timeout(const Duration(minutes: 3));

      // llama-server as the gateway started it (the model loads after the gateway is up: wait for it)
      for (var i = 0; i < 240 && !'${(await run(['status'])).stdout}'.contains('model ready'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final llamaPid = (Process.runSync('pgrep', ['-f', '--', '--host $sock']).stdout as String).trim()
          .split('\n').first;
      final cmdline = File('/proc/$llamaPid/cmdline').readAsStringSync().split('\x00');
      String after(String flag) => cmdline[cmdline.indexOf(flag) + 1];
      expect(after('--host'), sock, reason: 'H19-01: a Unix socket in the private folder');
      expect(cmdline, isNot(contains('--port')));
      expect(after('-np'), '1');
      expect(after('-c'), '8192');
      expect(cmdline, containsAll(['--log-disable', '--no-slots', '--no-webui', '--offline', '--no-cache-idle-slots']));
      expect(after('--cache-ram'), '0');
      // no TCP socket listening in llama-server at all: none of its descriptors is a listening TCP socket
      final inodes = <String>{
        for (final fd in Directory('/proc/$llamaPid/fd').listSync())
          if (RegExp(r'^socket:\[(\d+)\]$').firstMatch(Link(fd.path).targetSync()) case final m?) m.group(1)!,
      };
      final listening = <String>[
        for (final table in ['/proc/net/tcp', '/proc/net/tcp6'])
          if (File(table).existsSync())
            for (final line in File(table).readAsLinesSync().skip(1))
              if (line.trim().split(RegExp(r'\s+')) case final f when f.length > 9 && f[3] == '0A' && inodes.contains(f[9]))
                line,
      ];
      expect(listening, isEmpty, reason: 'llama-server opened a TCP port');
      expect((await FileStat.stat(sock)).mode & 0x1ff, 0x180);
      expect((await FileStat.stat(home)).mode & 0x1ff, 0x1c0);
      // H19-10: core dumps off for llama-server and for the gateway
      String coreLimit(String pid) =>
          File('/proc/$pid/limits').readAsLinesSync().firstWhere((l) => l.startsWith('Max core file size'));
      expect(coreLimit(llamaPid), matches(RegExp(r'^Max core file size\s+0\s+0\s')));
      expect(coreLimit('${serve.pid}'), matches(RegExp(r'^Max core file size\s+0\s+0\s')));
      final environ = File('/proc/$llamaPid/environ').readAsStringSync().split('\x00').where((e) => e.isNotEmpty)
          .map((e) => e.split('=').first).toSet();
      expect(environ, isNot(contains('LLAMA_ARG_SLOT_SAVE_PATH')));
      expect(environ, isNot(contains('SOLACE_E2E_SECRET')));
      expect(environ, contains('LLAMA_API_KEY'));
      // llama-server itself refuses anyone without the gateway's key, even this user on its own socket
      final direct = HttpClient()..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(InternetAddress(sock, type: InternetAddressType.unix), 0);
      final dreq = await direct.postUrl(Uri.parse('http://llama-server/v1/chat/completions'));
      dreq.write('{"messages":[{"role":"user","content":"hi"}]}');
      expect((await dreq.close()).statusCode, 401);
      direct.close(force: true);

      // pairing: the code the server printed
      r = await run(['pair']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final code = RegExp(r'Code: ([A-Z0-9-]+)').firstMatch('${r.stdout}')!.group(1)!;
      final link = GatewayHomeLink();
      final (pairing, info) = await link.pair('127.0.0.1:$port', code, 'E2E phone');
      expect(info.sha256, sum);
      final fp = RegExp(r'Certificate fingerprint: ([0-9a-f ]+)').firstMatch(out.toString())!.group(1)!.trim();
      expect(pairing.shownCertificate, fp, reason: 'the phone pinned what the server shows');
      await Future<void>.delayed(const Duration(seconds: 1));
      // llama-server is restarted with one slot for the one device; wait until the server says it is ready again
      for (var i = 0; i < 120; i++) {
        final s = await run(['status']);
        if ('${s.stdout}'.contains('model ready')) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      // a reply, streamed
      final model = link.runtime(pairing, trusts: (m) async => m.sha256 == sum ? null : 'not the model served');
      const secret = 'My private words about the lighthouse.';
      final words = await model.generate([
        {'role': 'system', 'content': 'You are a kind helper. Answer in one short sentence.'},
        {'role': 'user', 'content': secret},
      ], maxTokens: 24).toList();
      debugPrint('E2E reply from the model on the server (${words.length} pieces): ${words.join()}');
      expect(words.join().trim(), isNotEmpty);
      expect(words.length, greaterThan(1), reason: 'streamed in pieces');

      // Stop: the reply ends at once
      final got = <String>[];
      final done = Completer<void>();
      model.generate([{'role': 'user', 'content': 'Count slowly from one to two hundred, one number a line.'}],
          maxTokens: 600).listen((w) {
        got.add(w);
        if (got.length == 3) (model as HomeServerModel).cancelReply();
      }, onDone: done.complete, onError: (Object _) => done.complete());
      await done.future.timeout(const Duration(seconds: 30));
      expect(got.length, lessThan(100));

      // nothing about the conversation is on the server's disk
      final kept = Directory(home).listSync(recursive: true).whereType<File>().map((f) => f.uri.pathSegments.last)
          .toSet();
      // (admin.sock and llama.sock are the server's own sockets while it runs: no data, removed when it stops)
      expect(kept.difference({'cert.pem', 'key.pem', 'devices.json', 'config.json', 'admin.sock', 'llama.sock'}),
          isEmpty,
          reason: '$kept');
      for (final f in Directory(tmp.path).listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.gguf') || f.path.endsWith('.sock')) continue;
        expect(f.readAsStringSync(), isNot(contains('lighthouse')), reason: f.path);
      }
      expect(Directory('${tmp.path}/slots').existsSync(), isFalse, reason: 'no slot files');
      final devices = File('$home/devices.json').readAsStringSync();
      expect(devices, isNot(contains(pairing.token)));

      // unpair from the phone: its token stops working
      await link.unpair(pairing);
      await expectLater(link.status(pairing), throwsA(HomeLinkError.notPaired));
    } finally {
      serve.kill(ProcessSignal.sigint);
      await serve.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
        serve.kill(ProcessSignal.sigkill);
        return -1;
      });
      // llama-server goes with it, and so does the control socket
      await Future<void>.delayed(const Duration(seconds: 1));
      expect((Process.runSync('pgrep', ['-f', '--', '--host $sock']).stdout as String).trim(), isEmpty);
      expect(File('$home/admin.sock').existsSync(), isFalse);
      expect(File(sock).existsSync(), isFalse);
      await tmp.delete(recursive: true);
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));
}
