// Settings > Appearance (owner, 2026-11-14): light, dark or the device's own; the colour palette; the text size; the
// reading font; the serif for headings and the therapist's words. Every choice changes the whole app at once, so the
// preview at the top shows it before the person leaves the page. All of it stays on the device with the rest of the
// settings; the fonts are bundled (ui/theme.dart).
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/store.dart';
import 'premium.dart';
import 'theme.dart';

/// One line for the Settings row: what is chosen now.
String appearanceSummary(Settings s) {
  final mode = switch (s.themeMode) { 'light' => 'Light', 'dark' => 'Dark', _ => 'Matches your device' };
  final size = textSizes.firstWhere((e) => e.$1 == s.textSize, orElse: () => textSizes[1]).$2;
  final font = (fontChoices[s.font] ?? fontChoices[defaultFont]!).$2;
  return '$mode · ${accents[s.accent]?.name ?? 'Ocean'} · $font · $size text';
}

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.data.settings;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Future<void> set(void Function() f) async {
      feelChoice();
      f();
      await state.save();
      if (mounted) setState(() {});
    }

    final sizeIndex = textSizes.indexWhere((e) => e.$1 == s.textSize).clamp(0, textSizes.length - 1);
    final original = s.themeMode == 'system' && s.accent == 'ocean' && s.font == defaultFont && s.textSize == 1.0 && s.serif;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Appearance')),
      body: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(Space.xl - 4, 0, Space.xl - 4, Space.xxl), children: [
        const _Preview(),
        const SectionHeader('Light or dark'),
        SizedBox(width: double.infinity, child: SegmentedButton<String>(
          key: const Key('theme_mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_outlined), label: Text('Device')),
            ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
            ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => set(() => s.themeMode = v.first),
        )),
        Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(
            s.themeMode == 'system' ? 'Follows your device, so it turns dark in the evening if your device does.'
                : s.themeMode == 'dark' ? 'Dark, always: gentle on the eyes at night.' : 'Light, always.',
            style: t.bodySmall)),
        const SectionHeader('Colour'),
        Row(children: [ // five equal places, so no colour ever sits alone on a second row
          for (final MapEntry(key: id, value: a) in accents.entries)
            Expanded(child: _Swatch(id: id, accent: a, selected: s.accent == id, onTap: () => set(() => s.accent = id))),
        ]),
        SectionHeader('Text size', trailing: Text(textSizes[sizeIndex].$2, style: t.labelLarge?.copyWith(color: scheme.primary))),
        Row(children: [
          Text('A', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textScaler: TextScaler.noScaling),
          Expanded(child: Slider(key: const Key('text_size'), value: sizeIndex.toDouble(), min: 0,
              max: (textSizes.length - 1).toDouble(), divisions: textSizes.length - 1,
              label: textSizes[sizeIndex].$2, semanticFormatterCallback: (v) => textSizes[v.round()].$2,
              onChanged: (v) => set(() => s.textSize = textSizes[v.round()].$1))),
          Text('A', style: t.headlineSmall?.copyWith(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              fontWeight: FontWeight.w600), textScaler: TextScaler.noScaling),
        ]),
        Text('On top of your device\'s own text size.', style: t.bodySmall),
        const SectionHeader('Font'),
        for (final MapEntry(key: id, value: (family, name, about)) in fontChoices.entries)
          Padding(padding: const EdgeInsets.only(bottom: Space.s), child: _FontOption(
              id: id, family: family, name: name, about: about, selected: s.font == id,
              onTap: () => set(() => s.font = id))),
        Card(margin: const EdgeInsets.only(top: Space.s), child: SwitchListTile(
          key: const Key('serif'),
          title: const Text('Elegant serif'),
          subtitle: const Text('For large headings and Solace\'s words. Off: everything in your font.'),
          value: s.serif, onChanged: (v) => set(() => s.serif = v),
        )),
        const SizedBox(height: Space.l),
        Center(child: TextButton.icon(
          onPressed: original ? null : () => set(() {
            s.themeMode = 'system';
            s.accent = 'ocean';
            s.font = defaultFont;
            s.textSize = 1.0;
            s.serif = true;
          }),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Back to the original look'),
        )),
      ])),
    );
  }
}

/// A small piece of the app in the current choice: a line from the therapist, a reply, and the mood scale.
class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.l + 4),
      decoration: BoxDecoration(gradient: huesOf(context).therapist, borderRadius: BorderRadius.circular(24),
          boxShadow: softShadow(context)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PREVIEW', style: t.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.4,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: Space.s),
        Text('That sounds like a lot to carry. What would make tonight a little lighter?',
            style: voiceStyle(context, size: 24, color: Colors.white)),
        const SizedBox(height: Space.l),
        Align(alignment: Alignment.centerRight, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(18)),
          child: Text('Maybe an early night, and a short walk first.', style: t.bodyMedium),
        )),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.id, required this.accent, required this.selected, required this.onTap});
  final String id;
  final Accent accent;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(label: '${accent.name} colour', selected: selected, button: true, excludeSemantics: true,
        child: InkWell(key: Key('accent_$id'), onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(children: [
            AnimatedContainer(duration: Calm.quick, curve: Calm.curve, width: 52, height: 52,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: selected ? scheme.onSurface : Colors.transparent, width: 2)),
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: dark ? [accent.darkPrimary, accent.primary] : [accent.light, accent.primary, accent.deep])),
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                )),
            const SizedBox(height: Space.xs),
            FittedBox(fit: BoxFit.scaleDown, child: Text(accent.name, style: Theme.of(context).textTheme.labelMedium,
                maxLines: 1)),
          ]),
        )));
  }
}

class _FontOption extends StatelessWidget {
  const _FontOption({required this.id, required this.family, required this.name, required this.about,
      required this.selected, required this.onTap});
  final String id, family, name, about;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // a Material, not a coloured box, so the touch ripple shows on the card
    return Semantics(selected: selected, button: true, child: Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 1.5 : 1)),
      child: InkWell(key: Key('font_$id'), onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m + 2),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface)),
            const SizedBox(height: 2),
            Text(about, style: TextStyle(fontFamily: family, fontSize: 14, height: 1.35,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
          ])),
          const SizedBox(width: Space.m),
          AnimatedOpacity(opacity: selected ? 1 : 0, duration: Calm.quick,
              child: Icon(Icons.check_circle, color: scheme.primary)),
        ]),
      )),
    ));
  }
}
