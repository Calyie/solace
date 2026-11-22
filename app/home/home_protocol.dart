// Solace Home's pairing and request protocol, shared by the phone (app/home/home_client.dart) and the server
// (home_server/, which imports this file), so the two can never drift. Pure Dart: no Flutter, no network code.
//
// Pairing (docs/HOME_SERVER.md section 3). The server shows a one-time code of 12 characters (60 bits) while a
// pairing window is open (`solace-home pair`, at most 10 minutes, one device, five wrong tries). The phone connects
// over TLS without knowing the server's certificate yet, and records the SHA-256 of the certificate it was shown (its
// fingerprint). The code itself never crosses the network: each side proves it knows the code with an HMAC that
// binds the fingerprint the phone saw, the server's and the phone's random nonces, and (from the server) the device's
// new token. A machine in the middle (a hostile Wi-Fi) shows the phone its own certificate, so the phone's proof is
// made over the wrong fingerprint and the real server refuses it; it cannot make the server's proof without the code,
// so the phone refuses it too. Guessing the code from a recorded proof takes about 2^59 HMACs on average, far beyond
// the 10 minutes the window stays open. Once the server's proof checks, the phone pins that fingerprint for good and
// keeps the long random token; every later request carries the token and is refused unless the certificate matches.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SecretKeyData;
import 'package:cryptography/dart.dart';

/// The protocol's version; both sides refuse any other.
const homeProtocol = 1;

/// The paths the gateway answers, beside OpenAI's chat completions.
const pairStartPath = '/solace/v1/pair/start';
const pairFinishPath = '/solace/v1/pair/finish';
const statusPath = '/solace/v1/status';
const unpairPath = '/solace/v1/unpair';
const chatPath = '/v1/chat/completions';

/// The pairing code's characters: digits 2 to 9 and the capital letters without I and O (32, so 5 bits each).
const codeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/// The pairing code's length: 12 characters, 60 bits.
const codeLength = 12;

/// The most devices one server serves at once (one llama-server slot each).
const maxDevices = 4;

/// A new pairing code from [random] (the server's secure generator).
String newPairingCode(Random random) =>
    String.fromCharCodes([for (var i = 0; i < codeLength; i++) codeAlphabet.codeUnitAt(random.nextInt(32))]);

/// The code as shown and typed: three groups of four ("ABCD-EFGH-JKLM").
String showCode(String code) => [for (var i = 0; i < code.length; i += 4) code.substring(i, min(i + 4, code.length))]
    .join('-');

/// What the person typed, read as a code: upper case, spaces and dashes removed; null when it cannot be one (wrong
/// length or a character outside [codeAlphabet]). 0, 1, O and I are read as the letters they are never confused
/// with, as the alphabet leaves them out.
String? readCode(String typed) {
  final s = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '').replaceAll('0', 'O').replaceAll('1', 'I');
  if (s.length != codeLength) return null;
  for (final c in s.split('')) {
    if (!codeAlphabet.contains(c)) return null;
  }
  return s;
}

/// [n] random bytes from [random], as unpadded base64url text.
String randomText(Random random, int n) =>
    base64Url.encode([for (var i = 0; i < n; i++) random.nextInt(256)]).replaceAll('=', '');

/// Lower-case hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => _hex(const DartSha256().hashSync(bytes).bytes);

/// A certificate's fingerprint: the SHA-256 of its DER bytes, lower-case hex.
String certificateFingerprint(List<int> der) => sha256Hex(der);

/// What the server keeps of a device's token: its SHA-256 (the token itself is never written on the server).
String tokenHash(String token) => sha256Hex(utf8.encode(token));

/// The pairing proof of [role] ('phone' or 'server') over the certificate fingerprint the phone saw, both nonces and,
/// for the server's proof, the device id and the token's hash. HMAC-SHA256 under a key made from the code.
String pairProof(String code, String role, {required String fingerprint, required String serverNonce,
    required String phoneNonce, String deviceId = '', String tokenSha = ''}) {
  final key = const DartSha256().hashSync(utf8.encode('solace-home-pair-v$homeProtocol|$code')).bytes;
  final message = utf8.encode([role, fingerprint, serverNonce, phoneNonce, deviceId, tokenSha].join('|'));
  return _hex(DartHmac.sha256().calculateMacSync(message, secretKeyData: SecretKeyData(key), nonce: const []).bytes);
}

/// True when [a] and [b] are equal, in time that does not depend on where they differ.
bool sameText(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < max(x.length, y.length); i++) {
    diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The lines of [bytes] (UTF-8; ended by a line feed, a carriage return before it dropped), each at most [most]
/// characters: a longer line is a [LineTooLong] error, so neither side ever holds an endless line in memory (H19-07).
Stream<String> boundedLines(Stream<List<int>> bytes, int most) async* {
  var carry = '';
  await for (final chunk in utf8.decoder.bind(bytes)) {
    final parts = (carry + chunk).split('\n');
    carry = parts.removeLast();
    if (carry.length > most) throw const LineTooLong();
    for (final p in parts) {
      if (p.length > most + 1) throw const LineTooLong();
      yield p.endsWith('\r') ? p.substring(0, p.length - 1) : p;
    }
  }
  if (carry.isNotEmpty) yield carry;
}

/// A line longer than [boundedLines] allows.
class LineTooLong implements Exception {
  const LineTooLong();
}

/// The response header that names the SHA-256 of the model a reply was written with (H19-08): the phone checks it on
/// every reply against the model it checked, and checks again when it changes.
const servedModelHeader = 'x-solace-model';

/// A request body the gateway accepts, and nothing else: the conversation (roles system, user and assistant, text
/// only) and the reply's length. Everything the model is asked with (sampling, slot, template switches) is set by the
/// gateway itself, so a device can never reach another device's slot or change how the model runs.
class ChatRequest {
  ChatRequest(this.messages, this.maxTokens);
  final List<Map<String, String>> messages;
  final int maxTokens;

  static const maxMessages = 400, maxContent = 65536, mostTokens = 1024;

  Map<String, Object> toJson() => {'messages': messages, 'max_tokens': maxTokens, 'stream': true};

  /// The request in [j], or null with the reason it is refused.
  static (ChatRequest?, String?) from(Object? j) {
    if (j is! Map) return (null, 'not a JSON object');
    final extra = j.keys.where((k) => !const {'messages', 'max_tokens', 'stream', 'model'}.contains(k));
    if (extra.isNotEmpty) return (null, 'unknown field');
    final m = j['messages'];
    if (m is! List || m.isEmpty || m.length > maxMessages) return (null, 'messages');
    final out = <Map<String, String>>[];
    for (final e in m) {
      if (e is! Map || e.length != 2) return (null, 'a message');
      final role = e['role'], content = e['content'];
      if (role is! String || !const {'system', 'user', 'assistant'}.contains(role)) return (null, 'a role');
      if (content is! String || content.length > maxContent) return (null, 'a content');
      out.add({'role': role, 'content': content});
    }
    final t = j['max_tokens'] ?? 220;
    if (t is! int || t < 1 || t > mostTokens) return (null, 'max_tokens');
    if (j['stream'] != null && j['stream'] != true) return (null, 'stream');
    return (ChatRequest(out, t), null);
  }
}

/// The four bytes of the IPv4 address [a] carries: its own, or the one inside an IPv4-mapped IPv6 address
/// (::ffff:a.b.c.d); null for any other address.
List<int>? ipv4Of(InternetAddress? a) {
  if (a == null) return null;
  final raw = a.rawAddress;
  if (a.type == InternetAddressType.IPv4 && raw.length == 4) return raw;
  if (a.type == InternetAddressType.IPv6 && raw.length == 16 && raw.sublist(0, 10).every((b) => b == 0) &&
      raw[10] == 0xff && raw[11] == 0xff) {
    return raw.sublist(12);
  }
  return null;
}

/// Whether [a] is in 100.64.0.0/10, the range Tailscale gives its devices (also carrier-grade NAT's).
bool inTailscaleRange(InternetAddress? a) {
  final v4 = ipv4Of(a);
  return v4 != null && v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127;
}

/// Whether the other end of a Solace Home connection may be talked to at all, by the server (each connection it
/// accepts) and by the phone (each connection it opens) (owner, 2026-11-19: "only the home version can use tailscale
/// and only tailscale for remote access"): this computer (loopback), the home network (private IPv4 10/8, 172.16/12,
/// 192.168/16; IPv4 and IPv6 link-local), Tailscale (100.64.0.0/10 and its IPv6 range, inside fc00::/7), and other
/// unique-local IPv6. Anything else, an address on the open internet, is closed before TLS starts, so the server
/// never talks to the internet even on a computer with a public address or a forwarded port. An IPv4 address mapped
/// into IPv6 (::ffff:a.b.c.d) is judged as the IPv4 address it carries.
bool isLocalOrTailscale(InternetAddress? a) {
  if (a == null) return false;
  if (a.isLoopback) return true;
  var raw = a.rawAddress;
  if (a.type == InternetAddressType.IPv6) {
    final mapped = raw.length == 16 && raw.sublist(0, 10).every((b) => b == 0) && raw[10] == 0xff && raw[11] == 0xff;
    if (mapped) {
      raw = raw.sublist(12);
    } else {
      if (raw.length != 16) return false;
      if ((raw[0] & 0xfe) == 0xfc) return true; // fc00::/7, unique local (Tailscale: fd7a:115c:a1e0::/48)
      if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true; // fe80::/10, link-local
      return false;
    }
  }
  if (raw.length != 4) return false;
  final (x, y) = (raw[0], raw[1]);
  return x == 10 || // 10.0.0.0/8
      (x == 172 && y >= 16 && y <= 31) || // 172.16.0.0/12
      (x == 192 && y == 168) || // 192.168.0.0/16
      (x == 169 && y == 254) || // 169.254.0.0/16, link-local
      (x == 100 && y >= 64 && y <= 127) || // 100.64.0.0/10, Tailscale (carrier-grade NAT range)
      x == 127;
}
