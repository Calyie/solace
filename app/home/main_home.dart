// The Home build's entry point (docs/HOME_SERVER.md): Solace exactly as in lib/main.dart, plus the link to the person's
// own home server. Built only with:
//
//   flutter build <platform> -t home/main_home.dart --dart-define=SOLACE_HOME=true      (tools/home/build_home.sh)
//
// lib/main.dart, the default build's entry point, never imports this folder, so the default build has no network
// code at all (test/home/home_build_test.dart).
import 'package:solace/core/home_link.dart';
import 'package:solace/main.dart' as solace;

import 'home_link_impl.dart';

Future<void> main() async {
  // the wording ("nothing leaves your own devices"), the Android permission and the Linux network block all follow the
  // define, so a Home build made without it would say the wrong thing: refused
  if (!homeBuild) throw StateError('Build the Home entry point with --dart-define=SOLACE_HOME=true');
  homeLink = GatewayHomeLink();
  await solace.main(); // installs the default guards first; the paired server is allowed once the data is open
}
