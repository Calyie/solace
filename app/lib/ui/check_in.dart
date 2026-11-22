// The check-in before each session (TASKLIST B11; owner, 2026-11-07): how they are (0 to 10), the practice since last
// time with its distress at the start and the end (0 to 100; offered when the homework due is an exposure step, as in
// training: pipeline/series.py make_check_in), and the safety question, whose worrying answers show where to get help
// before the session starts. Every part may be left out, or the whole check-in skipped. It reaches the therapist in the
// first message exactly as formats.checkInText writes it; the therapist uses it in words and never reads numbers back.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/formats.dart';
import 'chat.dart';
import 'crisis.dart';
import 'emotion_sheet.dart';
import 'practices.dart' show openPractice;
import 'premium.dart';

/// The exposure-like steps whose practice gets distress ratings (pipeline/series.py PRACTICE_STEP).
final practiceStep = RegExp(r'ladder|rung|expos|step|without (wash|check|ask|search|googl|leav)|touch|stay|face|'
    r'approach|go (in|into|to|back)|drive|ride|sit with|resist|delay|wait|leave', caseSensitive: false);

/// The practice as training named it: the homework's first sentence, without its end stop, at most 90 characters.
String practiceLabel(String homework) {
  final label = homework.trim().split(RegExp(r'(?<=[.;])\s')).first.replaceAll(RegExp(r'[.;]+$'), '');
  return label.length > 90 ? label.substring(0, 90) : label;
}

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, required this.kind, this.practiceName = ''});
  final String kind;
  final String practiceName;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  int? _mood;
  bool _moodRead = false;
  String _did = ''; // 'yes', 'no', or '' (left out)
  int? _before, _after;
  String _safety = ''; // 'fine', 'thoughts', 'help', or '' (left out)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_moodRead) {  // a mood already tapped on the home screen today is the starting answer
      final state = AppScope.of(context);
      _mood = state.data.moods[isoDate(state.clock())];
      _moodRead = true;
      // the model reads the session's prompt while the person answers (core/session.dart prepare)
      state.newSession().prepare(widget.kind, practiceName: widget.practiceName);
    }
  }

  void _open(CheckIn c) => Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ChatScreen(kind: widget.kind, practiceName: widget.practiceName, checkIn: c)));

  /// "Yes" or "I need help now" is a crisis, recorded as the safety question's yes is in a session, and starts the
  /// 7-day watch (round 4 review, B-08: nothing was recorded, so the reliving gate stayed open and the next sessions
  /// opened with no gentle check). After "I need help now", trauma work does not start: grounding, a talk that is not
  /// trauma work, and Support are offered instead ([GroundFirstScreen]).
  Future<void> _start(String homework) async {
    final state = AppScope.of(context);
    final c = CheckIn(mood: _mood, practice: _did.isEmpty ? '' : practiceLabel(homework),
        start: _did == 'yes' ? _before : null, end: _did == 'yes' ? _after : null, safety: _safety);
    if (_safety == 'thoughts' || _safety == 'help') {
      // Round 9 review B, 9B-02: the crisis is recorded first and the support sheet opens at once; the one save of the
      // crisis and the mood runs while it shows, never before it (a large store takes seconds to write, and a stuck
      // save must not keep support away). Sessions do the same (core/session.dart).
      state.noteCrisis(_safety == 'help' ? 'needs help now, at the check-in' : 'thoughts of harm, at the check-in');
      if (_mood != null) state.recordMood(_mood!);
      unawaited(state.save());
      if (mounted) await showCrisisSheet(context, flagged: true);
    } else if (_mood != null) {
      await state.saveMood(_mood!);
    }
    if (!mounted) return;
    if (_safety == 'help' && traumaKinds.contains(widget.kind)) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GroundFirstScreen(checkIn: c)));
      return;
    }
    _open(c);
  }

  Widget _chips<T>(List<(String, T)> options, T selected, void Function(T) pick) => Wrap(spacing: 6, runSpacing: 6,
      children: [for (final (label, value) in options)
        ChoiceChip(label: Text(label), selected: selected == value, onSelected: (_) => setState(() => pick(value)))]);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final homework = AppScope.of(context).data.homeworkDue;
    final practice = homework.isNotEmpty && practiceStep.hasMatch(homework);
    final ready = _did != 'yes' || (_before != null && _after != null);
    final scale = [for (var i = 0; i <= 100; i += 10) ('$i', i)];
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Before we start')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Three quick questions, so Solace knows where you are today. Answer any, or none.'),
        const SizedBox(height: 20),
        Text('How are you right now?', style: t.titleMedium),
        const SizedBox(height: 8),
        MoodScale(value: _mood, name: 'checkin_mood', onChanged: (v) => setState(() => _mood = v)),
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _mood == null ? null : () => setState(() => _mood = null),
            child: const Text('Leave it out'))),
        const NameFeelingLink(), // optional: name the feeling too (ui/emotion_sheet.dart)
        if (practice) ...[
          const SizedBox(height: 24),
          Text('Your practice since last time', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(practiceLabel(homework)),
          const SizedBox(height: 8),
          _chips<String>([('I did it', 'yes'), ("I didn't", 'no'), ('Leave it out', '')], _did, (v) => _did = v),
          if (_did == 'yes') ...[
            const SizedBox(height: 14),
            const Text('How strong was the distress at the start?'),
            Text('0 is none. 100 is the most you can imagine.', style: t.bodySmall),
            const SizedBox(height: 6),
            _chips<int?>(scale, _before, (v) => _before = v),
            const SizedBox(height: 12),
            const Text('And at the end?'),
            const SizedBox(height: 6),
            _chips<int?>(scale, _after, (v) => _after = v),
          ],
        ],
        const SizedBox(height: 24),
        Text('Since we last talked, have you had thoughts of harming yourself or of not wanting to live?',
            style: t.titleMedium),
        const SizedBox(height: 8),
        _chips<String>([('No, I am OK', 'fine'), ('Yes', 'thoughts'), ('I need help now', 'help'), ('Leave it out', '')],
            _safety, (v) => _safety = v),
        const SizedBox(height: 28),
        FilledButton(key: const Key('check_in_start'), onPressed: ready ? () => _start(homework) : null,
            child: const Text('Start')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => _open(const CheckIn(skipped: true)), child: const Text('Skip the check-in')),
      ])),
    );
  }
}

/// The session kinds that are trauma work (core/session.dart traumaWork).
const traumaKinds = {'written_exposure', 'reliving'};

const groundFirstLine = 'You said you need help now, so the writing can wait for another day. Let\'s come back to the '
    'present first. Support is here at any time.';

/// After "I need help now" at the check-in before trauma work (round 4 review, B-08): the exercise does not start.
/// Grounding comes first, or a talk with Solace that is not trauma work, and Support is one tap away.
class GroundFirstScreen extends StatelessWidget {
  const GroundFirstScreen({super.key, required this.checkIn});
  final CheckIn checkIn; // what was answered, carried into the talk
  @override
  Widget build(BuildContext context) {
    final grounding = AppScope.of(context).library.where((p) => p.id == 'grounding-54321').firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('The present first'), actions: const [SupportButton()]),
      body: Readable(maxWidth: 720, child: ListView(key: const Key('ground_first'), padding: const EdgeInsets.all(20),
          children: [
        Text(groundFirstLine, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (grounding != null) ...[
          FilledButton.icon(key: const Key('ground_first_practice'), onPressed: () => openPractice(context, grounding),
              icon: const Icon(Icons.self_improvement), label: Text(grounding.title)),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(key: const Key('ground_first_talk'), onPressed: () => Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => ChatScreen(kind: 'daily_checkin', checkIn: checkIn))),
            icon: const Icon(Icons.chat_bubble_outline), label: const Text('Talk it through with Solace')),
        const SizedBox(height: 8),
        TextButton.icon(key: const Key('ground_first_support'), onPressed: () => showCrisisSheet(context),
            icon: const Icon(Icons.favorite_outline), label: const Text('Support')),
      ])),
    );
  }
}
