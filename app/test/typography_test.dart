// The type system (owner's pick, 2026-11-16: Newsreader for the headings and the therapist's words, Inter for the
// interface; ui/theme.dart): each role in its face, the optical size following the type size, Inter standing in for
// the Greek and Cyrillic Newsreader lacks, the old font choices moved to the new ones, and every bundled font file
// declared, licensed and used.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/theme.dart';

double? opsz(TextStyle? s) => s?.fontVariations?.firstWhere((v) => v.axis == 'opsz').value;

void main() {
  test('headings in Newsreader, the interface in Inter, each at its own optical size', () {
    final t = appTheme(Brightness.light).textTheme;
    for (final s in [t.displayLarge, t.headlineMedium, t.headlineSmall]) {
      expect(s?.fontFamily, 'Newsreader');
      expect(s?.fontFamilyFallback, ['Inter']);
      expect(opsz(s), greaterThanOrEqualTo(36)); // the display drawing
    }
    for (final s in [t.titleLarge, t.bodyMedium, t.labelSmall]) {
      expect(s?.fontFamily, 'Inter');
      expect(opsz(s), s!.fontSize!.clamp(14, 32));
      expect(s.fontWeight!.value, lessThanOrEqualTo(600)); // semibold at most: titles never shout
    }
    expect(t.bodyLarge?.height, 1.5);
  });

  test('the serif off: headings in the person\'s font, a step smaller and firmer', () {
    final t = appTheme(Brightness.light, const Look(font: 'lexend', serif: false)).textTheme;
    expect(t.headlineMedium?.fontFamily, 'Lexend');
    expect(t.headlineMedium?.fontWeight, FontWeight.w600);
    expect(t.bodyMedium?.fontFamilyFallback, ['Inter']); // Lexend has no Greek or Cyrillic
  });

  testWidgets('her words: Newsreader\'s text drawing in a bubble, its display drawing from 28 up', (tester) async {
    late TextStyle bubble, large;
    await tester.pumpWidget(MaterialApp(theme: appTheme(Brightness.light), home: Builder(builder: (context) {
      bubble = voiceStyle(context, size: 20);
      large = voiceStyle(context, size: 30);
      return const SizedBox();
    })));
    expect(bubble.fontFamily, 'Newsreader');
    expect(bubble.fontSize, 18);
    expect(opsz(bubble), 18);
    expect(bubble.fontSize! * bubble.height!, lessThanOrEqualTo(20 * 0.82 * 1.5)); // the call counts on this pitch
    expect(bubble.fontFamilyFallback, ['Inter']);
    expect(large.fontFamily, 'Newsreader');
    expect(opsz(large), 36);
  });

  test('a saved Figtree or Literata choice moves to Inter or Newsreader; the others stay', () {
    String font(Object? saved) => Settings.fromJson({'font': saved}).font;
    expect(font('figtree'), 'inter');
    expect(font(null), 'inter');
    expect(font('literata'), 'newsreader');
    for (final kept in ['atkinson', 'lexend', 'nunito', 'newsreader', 'inter']) {
      expect(font(kept), kept == 'inter' ? 'inter' : kept);
    }
    expect(Settings().font, defaultFont);
    expect(fontChoices.keys, containsAll(['inter', 'atkinson', 'lexend']));
    expect(fontChoices.keys.first, defaultFont);
  });

  test('every font file is declared, has its licence beside it, and nothing unused is bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final files = Directory('assets/fonts').listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();
    for (final f in files.where((f) => f.endsWith('.ttf'))) {
      expect(pubspec, contains('assets/fonts/$f'), reason: '$f is bundled but not declared');
      final family = f.split('-').first;
      expect(files, contains('OFL-$family.txt'), reason: '$f has no licence beside it');
      expect(File('assets/fonts/OFL-$family.txt').readAsStringSync(), contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
    for (final (family, _, _) in fontChoices.values) {
      expect(pubspec, contains('family: $family'));
    }
    expect(pubspec, contains('family: Newsreader'));
    expect(files.where((f) => f.endsWith('.ttf')).toSet(), {
      'Inter-Variable.ttf', 'Newsreader-Variable.ttf', 'AtkinsonHyperlegibleNext-Variable.ttf', 'Lexend-Variable.ttf',
      'Nunito-Variable.ttf', 'Figtree-Regular.ttf', 'Figtree-Bold.ttf', // Figtree: the PDF exports only
    });
  });
}
