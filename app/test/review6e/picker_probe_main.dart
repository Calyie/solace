// Round 6 review E, E-03: a device probe (an app entry point, not a unit test; built with
// `flutter build apk -t test/review6e/picker_probe_main.dart`). It makes the same call Solace's vision board makes
// (FilePicker.pickFiles(type: FileType.image), ui/vision_board.dart) and, like Solace, never asks for lost data and
// never clears the picker's copies at start. Run on the test emulator: start it, kill its process while the system
// picker is open, choose the photo, then look in the app's cache/file_picker and shared_prefs (adb root).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final marker = File('${dir.path}/probe_picked_once');
  String status;
  if (!marker.existsSync()) {
    marker.writeAsStringSync('1');
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('probe: picking')))));
    try {
      // PROBE_ANY=true: the call the transfer and model screens make (any file, the full-screen document picker)
      final picked = const bool.fromEnvironment('PROBE_ANY')
          ? await FilePicker.pickFiles(dialogTitle: 'Pick the transfer file')
          : await FilePicker.pickFiles(dialogTitle: 'Choose a photo', type: FileType.image);
      status = 'picked ${picked.length}';
    } catch (e) {
      status = 'error ${e.runtimeType}';
    }
  } else {
    status = 'restarted; no lost data asked for, nothing cleared (as Solace)';
  }
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text('probe: $status')))));
}
