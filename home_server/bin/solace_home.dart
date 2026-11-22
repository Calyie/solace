// solace-home: Solace Home's one program (docs/HOME_SERVER.md, home_server/README.md).
//
//   solace-home setup --model FILE --llama-server FILE [--port N] [--listen ADDRESS] [--gpu-layers auto|all|N] [--threads N] [--mlock]
//   solace-home serve                 start the gateway and llama-server, and keep them running
//   solace-home pair                  open a 10-minute pairing window and show its one-time code
//   solace-home devices               the paired devices
//   solace-home unpair ID|all         remove a device (its token stops working at once)
//   solace-home status                what is served, and the certificate's fingerprint
//   solace-home accept-unsigned SHA   serve a model the maker of Solace did not sign (each phone still asks)
import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../src/solace_home.dart';

const version = '1.0.0 (llama.cpp b11669)';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || const {'-h', '--help', 'help'}.contains(argv.first)) return _usage();
  final command = argv.first, rest = argv.sublist(1);
  try {
    switch (command) {
      case 'setup':
        await _setup(rest);
      case 'serve':
        await _serve();
      case 'pair' || 'devices' || 'unpair' || 'status':
        await _admin(command, rest);
      case 'accept-unsigned':
        await _acceptUnsigned(rest);
      case 'version' || '--version':
        stdout.writeln('solace-home $version');
      default:
        _usage();
        exitCode = 64;
    }
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on ModelRefused catch (e) {
    stderr.writeln('The model is not served: ${e.why}');
    exitCode = 1;
  } on NotPrivate catch (e) {
    stderr.writeln('Solace Home did not start: ${e.why}');
    exitCode = 1;
  } on SocketException catch (e) {
    stderr.writeln('Solace Home could not open its port or socket (${e.message}${e.osError == null ? '' : ': '
        '${e.osError!.message}'}). Is another copy running, or the port in use?');
    exitCode = 1;
  } on FormatException catch (e) {
    stderr.writeln('A file of Solace Home could not be read: ${e.message}');
    exitCode = 1;
  }
}

void _usage() => stdout.writeln('''solace-home $version

  solace-home setup --model FILE --llama-server FILE [--port N] [--listen ADDRESS] [--gpu-layers auto|all|N] [--threads N] [--mlock]
  solace-home serve                 start the gateway and the model (Ctrl+C stops both)
  solace-home pair                  open a 10-minute pairing window and show its one-time code
  solace-home devices               list the paired devices
  solace-home unpair ID|all         remove a device; its token stops working at once
  solace-home status                what is served, and the certificate's fingerprint
  solace-home accept-unsigned SHA   serve a model the maker of Solace did not sign (each phone still asks)

Files: ${homeDir().path} (SOLACE_HOME_DIR changes it)''');

Future<void> _setup(List<String> args) async {
  final home = await privateHome();
  final file = File('${home.path}/config.json');
  final c = await HomeConfig.read(file);
  final rest = [...args];
  // --mlock takes no value: llama-server keeps the model's weights in memory (README, "Swap and crash reports")
  if (rest.remove('--mlock')) c.mlock = true;
  if (rest.remove('--no-mlock')) c.mlock = false;
  if (rest.length.isOdd) throw StateError('Each option takes a value: ${rest.join(' ')}');
  for (var i = 0; i + 1 < rest.length; i += 2) {
    final v = rest[i + 1];
    switch (rest[i]) {
      case '--model':
        c.model = File(v).absolute.path;
      case '--llama-server':
        c.llamaServer = File(v).absolute.path;
      case '--port':
        c.port = int.parse(v);
      case '--listen':
        c.listen = v;
      case '--gpu-layers':
        c.gpuLayers = v;
      case '--threads':
        c.threads = int.parse(v);
      default:
        throw StateError('Unknown option ${rest[i]}');
    }
  }
  await c.write(file);
  final cert = await Certificate.inDir(home);
  stdout.writeln('Saved ${file.path}.\nCertificate fingerprint: ${showFingerprint(cert.fingerprint)}');
}

Future<void> _acceptUnsigned(List<String> args) async {
  if (args.length != 1 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(args.single)) {
    throw StateError('Give the model file\'s SHA-256 (64 lower-case hex characters).');
  }
  final home = await privateHome();
  final file = File('${home.path}/config.json');
  final c = await HomeConfig.read(file);
  if (!c.acceptUnsigned.contains(args.single)) c.acceptUnsigned.add(args.single);
  await c.write(file);
  stdout.writeln('This server will serve the model ${args.single}, which the maker of Solace did not sign. It has not '
      'been tested with Solace and its answers may be wrong, unkind or unsafe. Each phone asks its own person before '
      'using it.');
}

Future<void> _admin(String command, List<String> args) async {
  final home = homeDir();
  Map<String, Object?> answer;
  try {
    answer = await askGateway('${home.path}/admin.sock', command, args);
  } on StateError {
    // not running: the device list can still be read and changed on disk (H19-11: a server that could not start
    // used to leave the owner unable to unpair a phone without editing devices.json by hand)
    if (command != 'devices' && command != 'unpair') rethrow;
    final dir = await privateHome();
    final devices = DeviceStore(File('${dir.path}/devices.json'));
    await devices.load();
    answer = await adminDevices(command, args, devices, (ids) async {
      var n = 0;
      for (final id in ids) {
        if (await devices.remove(id)) n++;
      }
      return n;
    });
    if (answer['text'] != null) answer['text'] = '${answer['text']}\n(Solace Home is not running; the list on disk was used.)';
  }
  if (answer['error'] != null) throw StateError('${answer['error']}');
  stdout.writeln(answer['text']);
}

/// `devices` and `unpair`, the same whether the gateway answers them or they are done on disk while it is stopped.
Future<Map<String, Object?>> adminDevices(String command, List<String> args, DeviceStore devices,
    Future<int> Function(List<String> ids) unpair) async {
  if (command == 'devices') {
    final list = devices.devices;
    return {'text': list.isEmpty ? 'No paired devices.' : [
      for (final d in list) '${d.id}  ${d.name}  (paired ${d.paired}, slot ${d.slot})',
    ].join('\n')};
  }
  if (args.length != 1) return {'error': 'Give a device id from "solace-home devices", or all.'};
  final ids = args.single == 'all' ? [for (final d in devices.devices) d.id] : [args.single];
  final n = await unpair(ids);
  return {'text': n == 0 ? 'No such device.' : 'Unpaired $n device(s). Their tokens no longer work.'};
}

Future<void> _serve() async {
  // no core dumps of the gateway (and so of llama-server, which inherits the limit): a crash never writes the
  // conversations in memory to disk (H19-10)
  final dumps = noCoreDumps();
  if (!dumps.limitZero) {
    throw StateError('Solace Home did not start: core dumps could not be turned off for it, so a crash could write '
        'conversations to disk.');
  }
  if (Platform.isLinux && !dumps.notDumpable) {
    stderr.writeln('Note: this process could not be marked as not dumpable; its core limit is 0, so crash dumps that '
        'honour it (systemd-coredump does) keep nothing.');
  }
  final home = await privateHome();
  final configFile = File('${home.path}/config.json');
  if (await configFile.exists()) await makePrivate(configFile.path, 0x180);
  final config = await HomeConfig.read(configFile);
  if (config.model.isEmpty || config.llamaServer.isEmpty) {
    throw StateError('Run "solace-home setup --model FILE --llama-server FILE" first (the install script does).');
  }
  final llamaSocket = '${home.path}/llama.sock', adminPath = '${home.path}/admin.sock';
  checkSocketPath(llamaSocket);
  checkSocketPath(adminPath);
  stdout.writeln('Checking ${config.model} (SHA-256, the first time can take a minute)...');
  final model = await checkModel(File(config.model), acceptUnsigned: config.acceptUnsigned);
  final cert = await Certificate.inDir(home);
  final devices = DeviceStore(File('${home.path}/devices.json'));
  await devices.load();
  final random = Random.secure();
  final pairing = Pairing(random);

  // llama-server on a Unix socket in the private folder (H19-01), with one slot per device's fixed slot (H19-17);
  // before every restart the model is hashed again and must still be the file checked above (H19-08)
  final llama = LlamaServer(config, socket: llamaSocket, slots: () => devices.slotsNeeded, random: random,
      beforeStart: () async {
    if (!await model.file.exists()) throw ModelRefused('${model.name} is no longer there; it is not served.');
    final sum = await sha256OfFile(model.file);
    if (sum != model.sha256) {
      throw ModelRefused('${model.name} changed since solace-home serve started (its SHA-256 is now $sum), so it is '
          'not served. Put the checked file back, or restart solace-home serve to check the new one.');
    }
  });

  // the gateway and the control socket first, so the phones are told the model is loading (503) and `solace-home
  // unpair` works even when the model cannot load (H19-11)
  final gateway = Gateway(devices: devices, pairing: pairing, upstream: llama, model: model,
      fingerprint: cert.fingerprint, random: random, onDevicesChanged: () async => llama.restart());
  await gateway.bind(cert.context(), address: config.listen, port: config.port);

  final admin = AdminSocket(adminPath, (command, args) async {
    switch (command) {
      case 'pair':
        if (devices.full) return {'error': 'This server already serves $maxDevices devices. Unpair one first.'};
        final code = pairing.open();
        return {'text': 'Pairing is open for 10 minutes, for one device.\n\n    Code: ${showCode(code)}\n\n'
            'In Solace on the phone: Settings > Home server > Pair, with this computer\'s address and port '
            '${config.port}.\nThe phone will show this fingerprint once paired: ${showFingerprint(cert.fingerprint)}'};
      case 'devices' || 'unpair':
        return adminDevices(command, args, devices, gateway.unpair);
      case 'status':
        return {'text': 'Serving ${model.name} (${model.trustedBy}, ${model.light ? 'Light' : 'Standard'}), '
            'SHA-256 ${model.sha256}\nPort ${config.port}; model ${llama.describe}; '
            '${devices.devices.length} of $maxDevices devices paired.\nCertificate fingerprint: '
            '${showFingerprint(cert.fingerprint)}'};
    }
    return {'error': 'unknown command'};
  });
  try {
    await admin.start();
  } catch (_) {
    await gateway.close();
    rethrow;
  }

  stdout.writeln('Loading the model in llama-server (${devices.slotsNeeded} slot(s))...');
  llama.keepRunning();
  stdout.writeln('Solace Home is serving ${model.name} (${model.trustedBy}) on port ${config.port}.\n'
      'Certificate fingerprint: ${showFingerprint(cert.fingerprint)}\n'
      'Paired devices: ${devices.devices.length} of $maxDevices. To pair a phone, run "solace-home pair" in another '
      'terminal; "solace-home status" says when the model is ready.\nNothing about any conversation is written to '
      'disk. Ctrl+C stops the server.');

  final done = Completer<void>();
  void stop(ProcessSignal _) {
    if (!done.isCompleted) done.complete();
  }

  // Ctrl+C, a stop request, or the terminal closing (SIGHUP, which would otherwise end the gateway at once and leave
  // llama-server running with the model in memory): llama-server is stopped with it
  final subs = [ProcessSignal.sigint.watch().listen(stop), ProcessSignal.sigterm.watch().listen(stop),
      ProcessSignal.sighup.watch().listen(stop)];
  await done.future;
  for (final s in subs) {
    await s.cancel();
  }
  await admin.stop();
  await gateway.close();
  await llama.stop();
  stdout.writeln('Stopped.');
}
