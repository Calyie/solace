// Settings > Home server (Solace Home only; docs/HOME_SERVER.md): pair this device with Solace Home running on the
// person's own computer, see whether it answers, and unpair. The pairing (the server's address, its pinned certificate
// SHA-256 and this device's token) is kept in the encrypted settings on this device only. The network code is not
// here: it is in app/home/, compiled only into the Home build, which sets core/home_link.dart homeLink. In the default
// build this screen is never offered (homeLink is null).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/home_link.dart';
import '../core/model_import.dart' show UnsignedModel;
import '../main.dart' show loadTrainedModel, useHomeServer, homeModelTrust;
import 'model_files.dart' show askUnsignedModel;
import 'premium.dart';

/// Whether this build offers Settings > Home server.
bool get homeOffered => homeBuild && homeLink != null;

/// How the server lists this device.
String thisDeviceName() {
  if (kIsWeb) return 'a device';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isAndroid) return 'Android phone';
  if (Platform.isMacOS) return 'Mac';
  if (Platform.isLinux) return 'Linux computer';
  return 'a device';
}

/// Settings' line for it.
class HomeServerTile extends StatelessWidget {
  const HomeServerTile({super.key});
  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).data.settings.homeServer;
    return ListTile(contentPadding: EdgeInsets.zero, key: const Key('open_home_server'),
        leading: const Icon(Icons.dns_outlined), title: const Text('Home server'),
        subtitle: Text(p == null ? 'Use the model on your own computer' : 'Paired with ${p.host}:${p.port}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeServerScreen())));
  }
}

class HomeServerScreen extends StatefulWidget {
  const HomeServerScreen({super.key, this.trust = homeModelTrust});

  /// Why this device will not use a served model, or null (main.dart homeModelTrust; replaced in tests).
  final Future<String?> Function(AppState state, HomeModelInfo model) trust;
  @override
  State<HomeServerScreen> createState() => _HomeServerScreenState();
}

class _HomeServerScreenState extends State<HomeServerScreen> {
  final _address = TextEditingController(), _code = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final link = homeLink;
    if (link == null || _busy) return;
    final state = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = 'Pairing...';
    });
    String said;
    try {
      final (pairing, model) = await link.pair(_address.text, _code.text, thisDeviceName());
      // the served model must be one this device would use: built in, signed, or accepted here after the warning
      var why = await widget.trust(state, model);
      if (why != null && homeModelUnknownOnly(why) && mounted) {
        final UnsignedModel asked = (name: model.name, size: model.size, sha256: model.sha256);
        final yes = await askUnsignedModel(asked);
        if (yes && await state.acceptModel(model.sha256, model.name, model.size)) why = null;
      }
      final s = state.data.settings, before = s.homeServer;
      if (!await state.saveSetting(() => s.homeServer = pairing, () => s.homeServer = before)) {
        unawaited(link.unpair(pairing).catchError((Object _) {}));
        said = 'The pairing could not be saved on this device, so it was undone. Free some space, then try again.';
      } else {
        await state.letGoOfModel(); // the model on this device leaves memory: the server answers now
        useHomeServer(state, link, pairing);
        said = why == null
            ? 'Paired. Your home server answers from now on (${model.name}). Its certificate: '
                '${pairing.shownCertificate}. Check it matches what the computer showed.'
            : 'Paired, but this device will not use the model your home server serves: $why';
        _address.clear();
        _code.clear();
      }
    } on HomeLinkError catch (e) {
      said = e.sayToPerson;
    } catch (_) {
      said = HomeLinkError.unreachable.sayToPerson;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = said;
    });
  }

  Future<void> _check() async {
    final link = homeLink, p = AppScope.of(context).data.settings.homeServer;
    if (link == null || p == null || _busy) return;
    final state = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = 'Checking...';
    });
    String said;
    try {
      final model = await link.status(p);
      final why = await widget.trust(state, model);
      said = why == null ? 'Your home server answers, with ${model.name}.' : 'Your home server answers, but this device '
          'will not use its model: $why';
    } on HomeLinkError catch (e) {
      said = e.sayToPerson;
    } catch (_) {
      said = HomeLinkError.unreachable.sayToPerson;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = said;
    });
  }

  Future<void> _unpair() async {
    final link = homeLink, state = AppScope.of(context), s = state.data.settings, p = s.homeServer;
    if (link == null || p == null || _busy) return;
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Unpair this device?'),
      content: const Text('Your home server forgets this device and its key stops working. The model on this device '
          'answers again, if one is installed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(key: const Key('home_unpair_confirm'), onPressed: () => Navigator.pop(context, true),
            child: const Text('Unpair')),
      ],
    ));
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    var told = true;
    try {
      await link.unpair(p);
    } catch (_) {
      told = false; // forgotten here anyway; the computer can remove it with solace-home unpair
    }
    final saved = await state.saveSetting(() => s.homeServer = null, () => s.homeServer = p);
    if (saved) {
      link.allowOnly(null);
      await state.letGoOfModel();
      unawaited(loadTrainedModel(state));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = !saved ? 'This could not be saved, so the device is still paired. Try again.'
          : told ? 'Unpaired.' : 'Unpaired on this device. The server could not be reached, so remove this device '
              'there too: run "solace-home unpair" on the computer.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.data.settings.homeServer;
    final t = Theme.of(context).textTheme;
    InputDecoration box(String label, String hint) => InputDecoration(labelText: label, hintText: hint);
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Home server')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Solace Home runs the therapist model on your own computer, a Mac or a Linux machine (or a graphics '
            'server you rent for a day), so a smaller phone can use the Standard model. Sent to it, over an encrypted '
            'connection that only your paired computer can answer: $homeSentList. The safety check, the voice and '
            'everything you keep stay on this device. ${homeWhereLine(p)}', key: const Key('home_what_is_sent')),
        const SizedBox(height: Space.m),
        if (p == null) ...[
          Text('Pair this device', style: t.titleMedium),
          const SizedBox(height: Space.s),
          const Text('On the computer, run "solace-home pair". Type its address and port, and the code it shows.'),
          const SizedBox(height: Space.s),
          TextField(key: const Key('home_address'), controller: _address, enabled: !_busy,
              autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false,
              autocorrect: false, enableSuggestions: false, spellCheckConfiguration: PrivateKeyboard.spellCheck,
              maxLength: 300, buildCounter: quietCounter, keyboardType: TextInputType.url,
              decoration: box('Address and port', '192.168.1.20:8443')),
          const SizedBox(height: Space.s),
          TextField(key: const Key('home_code'), controller: _code, enabled: !_busy,
              autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false,
              autocorrect: false, enableSuggestions: false, spellCheckConfiguration: PrivateKeyboard.spellCheck,
              maxLength: 20, buildCounter: quietCounter, textCapitalization: TextCapitalization.characters,
              decoration: box('Code', 'ABCD-EFGH-JKLM'), onSubmitted: (_) => _pair()),
          const SizedBox(height: Space.m),
          FilledButton(key: const Key('home_pair'), onPressed: _busy ? null : _pair, child: const Text('Pair')),
        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Paired with ${p.host}:${p.port}', style: t.titleMedium),
            const SizedBox(height: Space.xs),
            Text('Since ${p.date}. Certificate: ${p.shownCertificate}', style: t.bodySmall),
            const SizedBox(height: Space.s),
            Text(state.modelStatus, key: const Key('home_status'), style: t.bodyMedium),
          ]))),
          const SizedBox(height: Space.m),
          OutlinedButton(key: const Key('home_check'), onPressed: _busy ? null : _check, child: const Text('Check now')),
          const SizedBox(height: Space.s),
          TextButton(key: const Key('home_unpair'), onPressed: _busy ? null : _unpair, child: const Text('Unpair')),
        ],
        if (_message != null) ...[
          const SizedBox(height: Space.m),
          Text(_message!, key: const Key('home_message'), style: t.bodyMedium),
        ],
        const SizedBox(height: Space.l),
        Text('Away from home, put this device and the computer on the same Tailscale network and use the computer\'s '
            'Tailscale address. Never open the port on your home router.', style: t.bodySmall),
      ])),
    );
  }
}

/// True when [why] (homeModelTrust) says only that the model is not signed by the maker, which the person may accept.
bool homeModelUnknownOnly(String why) => why.startsWith(unknownModelReason);

/// The start of homeModelTrust's answer for a model that is only unknown (not withdrawn, not for another version).
const unknownModelReason = 'it is not signed by the maker of Solace';
