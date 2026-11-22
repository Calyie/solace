// The design pass (2026-11-16, research report P1 10 and 18): the main screens meet Flutter's accessibility
// guidelines at a phone and a computer size, in light and dark. Text contrast at WCAG AA (4.5 to 1, 3 to 1 for large
// text), every tap target labelled, and tap targets at least 48 by 48 on a phone (Android's rule; the iPhone's is 44)
// and 44 by 44 on a computer, where a pointer is finer but the target still has to be easy to hit. And, because the
// guideline measures pixels (thin small text reads lighter than its colour), the theme's own pairs of text and
// background are checked exactly too, for every palette, light and dark, and the high-contrast variant.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/dates.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/load_guard.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/questionnaires.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/home.dart';
import 'package:solace/ui/memory_search.dart';
import 'package:solace/ui/model_files.dart';
import 'package:solace/ui/practices.dart';
import 'package:solace/ui/premium.dart';
import 'package:solace/ui/presence.dart';
import 'package:solace/ui/questionnaire.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/theme.dart';

import 'app_flow_test.dart' as flow;

typedef _Screen = Future<void> Function(WidgetTester tester);

Future<void> _pump(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(TherapistApp(state: state));
  await tester.pumpAndSettle();
}

AppState _demo(String mode) {
  final s = flow.makeState(demo: true)..modelInPlace = true;
  s.data.settings.themeMode = mode;
  return s;
}

Future<void> _tab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(Key('tab_$tab')));
  await tester.pumpAndSettle();
}

Map<String, _Screen> _screens(String mode) => {
      'the first-run welcome': (tester) async {
        final s = flow.makeState(chosen: false);
        s.data.settings
          ..onboarded = false
          ..themeMode = mode;
        await _pump(tester, s);
      },
      'the lock screen': (tester) async {
        final s = flow.makeState();
        s.data.settings
          ..themeMode = mode
          ..appLock = true
          ..passcode = {'x': 'y'};
        await _pump(tester, s);
      },
      'Today with no model': (tester) async {
        final s = flow.makeState()..modelInPlace = false;
        s.data.settings.themeMode = mode;
        await _pump(tester, s);
      },
      'Today': (tester) async => _pump(tester, _demo(mode)),
      'Talk': (tester) async {
        await _pump(tester, _demo(mode));
        await _tab(tester, 'Talk');
      },
      'Practices': (tester) async {
        await _pump(tester, _demo(mode));
        await _tab(tester, 'Practices');
      },
      'Progress': (tester) async {
        await _pump(tester, _demo(mode));
        await _tab(tester, 'Progress');
      },
      'You': (tester) async {
        await _pump(tester, _demo(mode));
        await _tab(tester, 'You');
      },
      'Settings': (tester) async {
        await _pump(tester, _demo(mode)..modelInPlace = false);
        Navigator.of(tester.element(find.byType(HomeShell)))
            .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
        await tester.pumpAndSettle();
      },
      'a session': (tester) async {
        await _pump(tester, _demo(mode));
        Navigator.of(tester.element(find.byType(HomeShell)))
            .push(MaterialPageRoute<void>(builder: (_) => const ChatScreen(kind: 'weekly_session')));
        await flow.frames(tester, ms: 1500);
        await tester.enterText(find.byType(TextField), 'I sketched on the tram three times this week.');
        await tester.tap(find.byKey(const Key('chat_send')));
        await flow.frames(tester, ms: 2500);
      },
    };

double _ratio(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final accent in accents.keys) {
    for (final b in Brightness.values) {
      for (final contrast in [false, true]) {
        test('$accent, ${b.name}${contrast ? ', more contrast' : ''}: every text colour on its background is AA', () {
          final theme = appTheme(b, Look(accent: accent, contrast: contrast));
          final s = theme.colorScheme;
          final hues = theme.extension<Hues>()!;
          final page = theme.scaffoldBackgroundColor;
          final pairs = <String, (Color, Color)>{
            'text on a card': (s.onSurface, s.surface),
            'text on the page': (s.onSurface, page),
            'quiet text on a card': (s.onSurfaceVariant, s.surface),
            'quiet text on the page': (s.onSurfaceVariant, page),
            'quiet text on a raised step': (s.onSurfaceVariant, s.surfaceContainer),
            'a link on a card': (s.primary, s.surface),
            'a link on the page': (s.primary, page),
            'a filled button': (s.onPrimary, s.primary),
            'a tonal button': (s.onPrimaryContainer, s.primaryContainer),
            'an error': (s.error, s.surface),
            'the white pill on Solace\'s card': (hues.onPill, Colors.white),
            for (final (i, c) in hues.therapist.colors.indexed) 'white words on Solace\'s card, stop $i': (Colors.white, c),
          };
          for (final MapEntry(key: what, value: (fg, bg)) in pairs.entries) {
            // white words on the gradient's lightest stop are large (the serif at 23 and up, titles in bold): 3 to 1
            final need = what.startsWith('white words') ? 3.0 : 4.5;
            expect(_ratio(fg, bg), greaterThanOrEqualTo(need), reason: '$what: ${_ratio(fg, bg).toStringAsFixed(2)}');
          }
        });
      }
    }
  }
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  for (final (device, size, ratio, platform, target) in [
    ('a phone (390 x 844)', const Size(390, 844), 3.0, TargetPlatform.iOS, 48.0),
    ('a computer (1440 x 900)', const Size(1440, 900), 2.0, TargetPlatform.macOS, 44.0),
  ]) {
    for (final mode in ['light', 'dark']) {
      for (final MapEntry(key: name, value: screen) in _screens(mode).entries) {
        testWidgets('$name on $device, $mode: contrast, labels and tap targets', (tester) async {
          tester.view.physicalSize = size * ratio;
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.reset);
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
          addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.menu, null));
          final semantics = tester.ensureSemantics();
          await screen(tester);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(target == 48 ? androidTapTargetGuideline : iOSTapTargetGuideline));
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
          await flow.frames(tester, ms: 400);
        }, variant: TargetPlatformVariant.only(platform));
      }
    }
  }

  // The remaining weak spots of the design review (2026-11-16).
  // 1. The mood scale: one slider with word labels, its whole row a finger's height, at every phone width from 320.
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('the mood scale at $width wide: a 48-high row across the card, a tap at each point chooses it, a '
        'slide chooses where it lifts, the keyboard moves it, and a screen reader hears one adjustable control',
        (tester) async {
      _phone(tester, Size(width, 800));
      final state = flow.makeState(demo: true)..modelInPlace = true;
      await _pump(tester, state);
      final row = find.ancestor(of: find.byKey(const Key('mood_0')), matching: find.byType(GestureDetector)).first;
      final rect = tester.getRect(row);
      final card = tester.getRect(find.ancestor(of: row, matching: find.byType(Card)).first);
      expect(rect.height, greaterThanOrEqualTo(48), reason: 'the whole row takes the touch');
      expect(rect.width, greaterThanOrEqualTo(card.width - 2 * Space.l - 1), reason: 'across the card');
      expect(find.text('Tap or slide to choose'), findsOneWidget, reason: 'nothing chosen yet, and no point marked');
      String? today() => state.data.moods[isoDate(state.clock())]?.toString();
      for (var i = 0; i <= 10; i++) {
        final point = tester.getRect(find.byKey(Key('mood_$i')));
        expect(point.center.dy, closeTo(rect.center.dy, 1));
        await tester.tap(find.byKey(Key('mood_$i')));
        await tester.pumpAndSettle();
        expect(today(), '$i', reason: 'a tap at point $i');
        expect(find.text('${moodWords[i]}  $i out of 10', findRichText: true), findsOneWidget,
            reason: 'its word shows');
      }
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('mood_2'))));
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('mood_5'))));
      await tester.pump();
      expect(today(), '10', reason: 'nothing is saved while the finger slides');
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('mood_8'))));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(today(), '8', reason: 'chosen where the finger lifts');
      Focus.of(tester.element(find.byKey(const Key('mood_0')))).requestFocus();
      await tester.pump();
      for (final (key, want) in [(LogicalKeyboardKey.arrowLeft, '7'), (LogicalKeyboardKey.arrowRight, '8'),
          (LogicalKeyboardKey.home, '0'), (LogicalKeyboardKey.end, '10')]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(today(), want, reason: '$key');
      }
      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(find.byKey(const Key('mood_5')));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.value, '10 out of 10, Very good');
      expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  // 2. The model status: each file on its own line, with a clear state and a short sentence; the full words on demand.
  testWidgets('Settings shows each file on its own line with its state, a way to try again, and details on demand',
      (tester) async {
    _phone(tester, const Size(390, 844));
    final state = flow.makeState(demo: true)..modelInPlace = false;
    await _pump(tester, state);
    Navigator.of(tester.element(find.byType(HomeShell)))
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    String said(Engine e) => [
          for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(Key('file_${e.name}')),
              matching: find.byType(Text)))) t.data,
        ].join(' | ');
    for (final e in Engine.values) {
      expect(said(e), contains('Not added'), reason: '$e');
    }
    expect(find.text(filesToPick), findsOneWidget, reason: 'what to pick, while one is not added');
    expect(find.byKey(const Key('model_status')), findsNothing, reason: 'the full words wait for Details');
    await tester.ensureVisible(find.byKey(const Key('files_details')));
    await tester.tap(find.byKey(const Key('files_details')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('model_status'))).data, state.modelStatus);
    // each state, in its word
    state
      ..modelInPlace = true
      ..useModel(const _Ready(), 'Ready: model-light.gguf')
      ..reportVoice('Voice: Checking the voice files...')
      ..reportStoppedLoad(const StoppedLoad(Engine.classifier, ''))
      ..reportSafety(stoppedSafetyStatus);
    await tester.pumpAndSettle();
    expect(said(Engine.model), allOf(contains('Ready'), contains('Solace answers with it')));
    expect(said(Engine.voice), contains('Getting ready'));
    expect(said(Engine.classifier), allOf(contains('Not loaded'), contains('stopped while loading')));
    expect(find.byKey(const Key('try_load_classifier')), findsOneWidget, reason: 'Try again, under its file');
    expect(find.text(filesToPick), findsNothing, reason: 'none is missing now');
    state.data.settings.classifierOn = false;
    state
      ..clearStoppedLoad(Engine.classifier)
      ..useVoice(const _Speaks(), 'Voice: Solace speaks.');
    await tester.pumpAndSettle();
    expect(said(Engine.classifier), contains('Off'));
    expect(said(Engine.voice), contains('Ready'));
    expect(tester.takeException(), isNull);
  });

  // 3. Titles are never cut short on a phone, from 320 wide: a screen's title in its bar takes two lines, a step
  // smaller, when one does not hold it. (The session's own bar is ui/chat.dart's.)
  for (final width in [320.0, 360.0]) {
    testWidgets('at $width wide no title is cut short: practices, past sessions, the check-up, Settings, Today, Talk',
        (tester) async {
      _phone(tester, Size(width, 700));
      final state = flow.makeState(demo: true)..modelInPlace = true;
      await _pump(tester, state);
      final cut = <String>[];
      void scan(String where) {
        void visit(RenderObject o) {
          if (o is RenderParagraph && o.attached && o.hasSize && o.didExceedMaxLines &&
              (o.text.style?.fontSize ?? 0) >= 16) {
            cut.add('$where: "${o.text.toPlainText()}"');
          }
          o.visitChildren(visit);
        }
        visit(tester.binding.rootElement!.renderObject!);
      }

      for (final tab in ['Today', 'Talk']) {
        final place = find.byKey(Key('tab_$tab'));
        if (place.evaluate().isNotEmpty) await tester.tap(place);
        await tester.pumpAndSettle();
        scan(tab);
      }
      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      Future<void> open(String name, Widget screen) async {
        nav.push(MaterialPageRoute<void>(builder: (_) => screen));
        await flow.frames(tester, ms: 1200);
        scan(name);
        nav.pop();
        await flow.frames(tester, ms: 800);
      }
      for (final p in state.library.where((p) => p.guided)) {
        await open(p.title, PracticePlayer(practice: p, version: p.versions.keys.first));
      }
      for (final r in state.data.sessions) {
        await open('a past ${r.kind}', PastSessionView(record: r));
      }
      await open('the check-up', const QuestionnaireFlow(list: [phq9, gad7]));
      await open('Settings', const SettingsScreen());
      expect(cut, isEmpty);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  // 4. The welcome is balanced on every phone height: the light grows with the room, and there is never more empty
  // space above it than between the words and Begin.
  for (final size in [const Size(320, 568), const Size(375, 667), const Size(390, 844), const Size(440, 956)]) {
    testWidgets('the welcome on a ${size.width.toInt()} x ${size.height.toInt()} phone is balanced', (tester) async {
      _phone(tester, size);
      final s = flow.makeState(chosen: false);
      s.data.settings.onboarded = false;
      await _pump(tester, s);
      final light = tester.getRect(find.byType(AbstractPresence));
      final top = tester.getRect(find.byKey(const Key('onb_support'))).bottom;
      final words = tester.getRect(find.textContaining('A calm, private place')).bottom;
      final begin = tester.getRect(find.byKey(const Key('onb_next'))).top;
      expect(light.width, inInclusiveRange(140, 340));
      if (size.height >= 800) expect(light.width, greaterThanOrEqualTo(260), reason: 'a tall phone: a large light');
      expect(light.top - top, lessThanOrEqualTo(begin - words + 1), reason: 'no more space above the light than below '
          'the words (${light.top - top} above, ${begin - words} below)');
      expect(light.center.dx, closeTo(size.width / 2, 1));
      // the step dots sit in the middle, over the words
      final dots = tester.getRect(find.bySemanticsLabel(RegExp(r'^Step 1 of')));
      expect(dots.center.dx, closeTo(size.width / 2, 1));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// A trained model in place (any runtime other than the stand-in).
class _Ready extends StandInModel {
  const _Ready();
  @override
  String get name => 'model-light.gguf';
}

/// A voice that is there.
class _Speaks extends StubVoice {
  const _Speaks();
  @override
  bool get available => true;
}
