// Review round 4, A: the transfer file carries this device's own lock settings, including the app passcode's salted
// hash (six digits: a million guesses offline), although the receiving device ignores them (importInto keeps its own).
// Whoever gets the file and its code learns the source phone's app passcode. Failed on 5bdac57; fixed in round 4.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';

void main() {
  test('a transfer file does not carry the app passcode hash or other device-only lock state', () async {
    final data = AppData()
      ..settings.appLock = true
      ..settings.passcode = {'salt': 'c2FsdHNhbHRzYWx0c2FsdA==', 'hash': 'aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaA=='}
      ..settings.lockFails = 3;
    const code = 'ABCDEFGHJKMNPQRS';
    final file = await TransferFile.seal(data, code);
    final opened = await TransferFile.open(file, code); // what anyone holding the file and its code reads
    print('passcode in the file: ${opened.settings.passcode}; lock fails: ${opened.settings.lockFails}');
    expect(opened.settings.passcode, isNull, reason: 'the receiving device never uses it');
  });
}
