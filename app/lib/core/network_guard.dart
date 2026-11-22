// AIR-3 (security review 2026-11-14; owner, 2026-11-16): Solace's own network guards, on every device, before the
// first screen (main.dart). The app has no network code; these stop anything inside it (a package's forgotten path
// included) that would try. They add to the operating system's own blocks where a device has one: Android (no internet
// permission), the Mac (its sandbox, no network entitlement) and Linux (a seccomp filter set by linux/runner/main.cc).
// The iPhone gives an ordinary app no such block, so there these, with the native guard in ios/Runner/AppDelegate.swift,
// are the app's own defence, and turning off Mobile Data for Solace is the person's (docs/SECURITY.md section 7).
//
// Two guards in Dart:
//   - HttpOverrides: making a web client throws, so no web request or web socket can be made through dart:io's
//     HttpClient in this isolate.
//   - IOOverrides: Socket.connect, Socket.startConnect and ServerSocket.bind throw for every internet address and
//     host name. A Unix-domain address (a local socket file, never off the device) is let through, as the Linux
//     filter lets it through for D-Bus and the sound server.
// Each refusal throws [NetworkRefused] and is recorded once per kind through ErrorLog (its type only). Limits (round 10
// review B, R10B-03): both overrides are per isolate, so a background isolate (Isolate.run, llamadart's own) starts
// without them; Dart gives no hook for SecureSocket, RawSocket, datagram sockets or InternetAddress.lookup. The
// privacy test checks that the app's code uses none of these (docs/SECURITY.md section 7).
import 'dart:io';

import 'error_log.dart';

/// Something inside Solace tried the network, and was stopped before any connection was made.
class NetworkRefused implements Exception {
  const NetworkRefused();
  @override
  String toString() => 'Solace never connects to the internet, so this was stopped.';
}

/// Installs both guards for the rest of this run (main.dart, before runApp).
void installNetworkGuards() {
  HttpOverrides.global = _NoWebClient();
  IOOverrides.global = _NoInternetSockets();
}

final _recorded = <String>{};

Never _refuse(String kind) {
  if (_recorded.add(kind)) ErrorLog.record(const NetworkRefused());
  throw const NetworkRefused();
}

Future<T> _refused<T>(String kind) {
  try {
    _refuse(kind);
  } catch (e) {
    return Future<T>.error(e);
  }
}

/// A Unix-domain socket address: a file on this device, never a network.
bool _local(Object? address) => address is InternetAddress && address.type == InternetAddressType.unix;

class _NoWebClient extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _refuse('web');
}

final class _NoInternetSockets extends IOOverrides {
  @override
  Future<Socket> socketConnect(host, int port, {sourceAddress, int sourcePort = 0, Duration? timeout}) =>
      _local(host) ? super.socketConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort,
          timeout: timeout) : _refused('connect');

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(host, int port, {sourceAddress, int sourcePort = 0}) =>
      _local(host) ? super.socketStartConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort)
          : _refused('connect');

  @override
  Future<ServerSocket> serverSocketBind(address, int port, {int backlog = 0, bool v6Only = false, bool shared = false}) =>
      _local(address) ? super.serverSocketBind(address, port, backlog: backlog, v6Only: v6Only, shared: shared)
          : _refused('listen');
}

/// The sentence Settings > Private by design shows about the operating system's own network block on this device.
/// [os] is Platform.operatingSystem and [environment] the process environment (tests give their own).
String networkBlockNote({String? os, Map<String, String>? environment}) {
  switch (os ?? Platform.operatingSystem) {
    case 'android':
      return 'Android itself keeps Solace off the internet: Solace does not have the internet permission.';
    case 'macos':
      return 'macOS itself keeps Solace off the network: its sandbox gives Solace no network access.';
    case 'linux':
      return (environment ?? Platform.environment)['SOLACE_NET_BLOCK'] == 'on'
          ? 'Linux itself keeps Solace off the network: as Solace starts, it is blocked from making any internet '
              'connection, and so is anything it starts.'
          : 'Linux\'s own network block is not on for this copy of Solace (it could not be set as Solace started, '
              'or this is a test build), so here Solace relies on having no network code.';
    case 'ios':
      return 'An iPhone gives apps like Solace no switch to block the internet for themselves, so Solace stops every '
          'internet request inside the app. You can also turn off Mobile Data for Solace in Settings > Mobile '
          'Service (or Cellular). Wi-Fi cannot be turned off for one app; aeroplane mode with Wi-Fi off blocks '
          'everything.';
    default:
      return 'Solace has no network code and never connects to the internet.';
  }
}
