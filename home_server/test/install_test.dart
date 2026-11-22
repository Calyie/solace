// The install scripts install the solace-home program only when it matches the SHA-256 they pin (H19-12): a program
// beside the script with no pin, or another SHA-256, is refused and nothing is installed. Runs common.sh's
// install_gateway with bash in a scratch folder (no Dart on its PATH, so it cannot build from source instead).
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String program, prefix;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('solace_install');
    await File('install/common.sh').copy('${dir.path}/common.sh');
    final os = '${(await Process.run('uname', ['-s'])).stdout}'.trim().toLowerCase();
    final arch = '${(await Process.run('uname', ['-m'])).stdout}'.trim();
    program = '${dir.path}/solace-home-$os-$arch';
    await File(program).writeAsString('#!/bin/sh\necho solace-home\n');
    prefix = '${dir.path}/prefix';
  });
  tearDown(() => dir.delete(recursive: true));

  Future<ProcessResult> install(String pin) => Process.run('bash', ['-c',
    '. "${dir.path}/common.sh"; gateway_pin() { echo "$pin"; }; install_gateway'],
      environment: {'PATH': '/usr/bin:/bin', 'HOME': dir.path, 'SOLACE_HOME_PREFIX': prefix},
      includeParentEnvironment: false);

  String sha(String path) => '${Process.runSync('sha256sum', [path]).stdout}'.split(' ').first;

  test('a program that matches its pin is installed', () async {
    final r = await install(sha(program));
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(sha('$prefix/bin/solace-home'), sha(program));
  });

  test('a program with another SHA-256 is refused, and nothing is installed', () async {
    final r = await install('0' * 64);
    expect(r.exitCode, isNot(0));
    expect('${r.stderr}', contains('not installed'));
    expect(File('$prefix/bin/solace-home').existsSync(), isFalse);
    expect(File('$prefix/bin/solace-home.part').existsSync(), isFalse);
  });

  test('a program this script pins no SHA-256 for is refused', () async {
    final r = await install('');
    expect(r.exitCode, isNot(0));
    expect('${r.stderr}', contains('pins no SHA-256'));
    expect(File('$prefix/bin/solace-home').existsSync(), isFalse);
  });

  test('the shipped scripts pin no program they were not given, and the Mac script never unquarantines before the '
      'check', () {
    final common = File('install/common.sh').readAsStringSync();
    expect(RegExp(r'darwin-arm64\) echo "([0-9a-f]{64})?"').hasMatch(common), isTrue);
    final mac = File('install/install_macos.sh').readAsStringSync();
    expect(mac, isNot(contains('xattr -d com.apple.quarantine "\$PREFIX/bin/solace-home"')));
    final check = common.indexOf('[ "\$got" = "\$pin" ]'), unquarantine = common.indexOf('xattr -d com.apple.quarantine');
    expect(check, greaterThan(0));
    expect(unquarantine, greaterThan(check));
  });
}
