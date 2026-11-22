// Help me start (PLAN 13 ADHD tools, TASKLIST B3): the person names what they are putting off; the therapist splits it
// into three to six small steps, the first about two minutes, exactly as it was trained to (pipeline/split_data.py: the
// session's system prompt with today's memory, then the split instruction); then they start the first step together,
// with a timer that visibly shrinks (externalising time, Barkley). The steps can go into today's plan.
import 'dart:async';

import 'package:flutter/material.dart' hide Step;

import '../app_state.dart';
import '../core/check_in_guard.dart' show ReplyScreen, linkGroup, phoneGroup;
import '../core/dates.dart';
import '../core/formats.dart';
import '../core/model.dart';
import '../core/plans.dart';
import '../core/safety.dart';
import '../core/session.dart' show pastesInIsolate, runWorkApart;
import '../core/therapist.dart' show therapistNameFor;
import 'crisis.dart';
import 'plan_today.dart' show parkThought;
import 'premium.dart';
import 'theme.dart';

/// The phrase rules on a task (round 5 review, D-16): past [pastesInIsolate] characters in a background isolate, as
/// sessions, notes and pastes read long text (round 4 review, B-17; 3,000 characters since round 9 review B, 9B-03),
/// never on the interface thread; the task box takes up to 20,000 characters, which took up to 128 ms of rule work on a
/// laptop there, several times that on a phone.
/// A fault of the rules is recorded by the caller and reads as no sign, as in sessions; the classifier still reads it.
Future<SafetyResult> readTask(String task, {SafetyCheck rules = const SafetyCheck()}) async {
  if (task.length <= pastesInIsolate) return rules.check(task, sessionKind: 'daily_checkin');
  return runWorkApart(() => rules.check(task, sessionKind: 'daily_checkin'));
}

class HelpMeStartScreen extends StatefulWidget {
  const HelpMeStartScreen({super.key, this.task = ''});
  final String task;
  @override
  State<HelpMeStartScreen> createState() => _HelpMeStartScreenState();
}

class _HelpMeStartScreenState extends State<HelpMeStartScreen> {
  late final _task = TextEditingController(text: widget.task);
  List<(String, int)> _steps = [];
  bool _busy = false, _added = false;
  bool _support = false; // the split held a way or a means to harm: Support is offered instead of steps
  String? _message;
  int? _running; // the step being done now
  int _left = 0, _total = 1; // seconds
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _task.dispose();
    super.dispose();
  }

  Future<void> _split() async {
    final state = AppScope.of(context);
    final task = _task.text.trim();
    if (task.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
      _support = false;
    });
    // the phrase rules, as every session message (security review 2026-11-14, SAFE-2); a worry from them opens support
    // instead of turning the words into timed steps. The trained classifier and its question are not used here (owner,
    // 2026-11-15: the question was an annoyance, and nothing below 90 percent precision may interrupt)
    SafetyLevel rules;
    try {
      rules = (await readTask(task)).level;
    } catch (e) {
      // the rules failed on this text (never expected): recorded, never silent
      rules = SafetyLevel.none;
      state.data.safetyEvents.add({'date': isoDate(state.clock()), 'level': 'error', 'reason': 'rules ${e.runtimeType}'});
      unawaited(state.save());
    }
    // a crisis is recorded even if the screen has gone while a long task was read: only showing it needs the screen
    // round 7 review, H7-07 (owner, 2026-11-15: precision first): only a crisis opens support here; a worry from the
    // rules shows nothing and leaves no record, and the split goes on
    if (rules == SafetyLevel.crisis) {
      state.data.safetyEvents.add({'date': isoDate(state.clock()), 'level': 'crisis', 'reason': 'help me start'});
      // as in sessions, a crisis starts the gentle check of the next 7 days (core/session.dart _crisis)
      state.data.safetyWatch = {'since': state.clock().toIso8601String(), 'reason': 'help me start'};
      unawaited(state.save());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _steps = [];
        _message = _heavy;
      });
      await showCrisisSheet(context, flagged: true);
      return;
    }
    if (!mounted) return;
    await _splitNow(task);
  }

  static const _heavy = 'That sounds like a lot to carry. Support is here now, and you can talk it through with '
      'Solace.';

  Future<void> _splitNow(String task) async {
    final state = AppScope.of(context);
    final now = state.clock();
    final String reply;
    try {
      final system = state.prompts.appSystem(kind: 'daily_checkin', date: dayLabel(now), mode: state.data.settings.mode,
          memory: state.data.memoryFor(now), therapistName: therapistNameFor(state.data.settings.portrait));
      reply = await state.model.generate([
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': state.prompts.splitInstruction(task)},
      ], maxTokens: 200).join();
    } catch (_) {
      // the model could not answer: the button works again, and the screen says so plainly (F-17)
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'I could not split that one just now. Please try again in a moment.';
        });
      }
      return;
    }
    if (!mounted) return;
    // the steps are the model's own words, screened as every reply is (core/check_in_guard.dart ReplyScreen; AI-4): a
    // step that quotes the mode line is left out, and a split with a way or a means to harm in it is never turned into
    // timed steps; only the rule group is recorded
    final screen = ReplyScreen(modeLine: modeLines[state.data.settings.mode] ?? '');
    final groups = <String>{}, steps = <(String, int)>[];
    try {
      for (final step in parseSplit(reply)) {
        final group = screen.groupOf(step.$1);
        if (group == null) {
          steps.add(step);
        } else {
          groups.add(group);
        }
      }
    } catch (_) {
      // the reply could not be read (OWASP review 2026-11-14, OW-A10-1): the button works again, never busy for good
      setState(() {
        _busy = false;
        _message = 'I could not split that one. Try saying it another way.';
      });
      return;
    }
    // a step that gives a phone number is left out as a quote of the mode line is (round 5 review, D-12): it is not a
    // means, so the other steps still show
    final means = groups.any((g) => g != 'mode line' && g != phoneGroup && g != linkGroup); // a link too (F6-09)
    if (groups.isNotEmpty) {
      for (final g in groups) {
        state.data.safetyEvents.add({'date': isoDate(now), 'level': 'output', 'reason': g});
      }
      unawaited(state.save());
    }
    setState(() {
      _busy = false;
      _steps = means ? [] : steps;
      _support = means;
      if (means) {
        _message = "I'm not able to help with that one, but I'm here with you. Support has people you can talk to "
            'right now.';
      } else if (steps.isEmpty) {
        _message = state.model is StandInModel
            ? 'Help me start needs the trained model. Add it in Settings, then try again.'
            : 'I could not split that one. Try saying it another way.';
      }
    });
  }

  void _start(int i) {
    _timer?.cancel();
    setState(() {
      _running = i;
      _total = _left = _steps[i].$2.clamp(1, 60) * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  void _next() {
    final i = _running! + 1;
    if (i < _steps.length) {
      _start(i);
    } else {
      _timer?.cancel();
      setState(() {
        _running = null;
        _message = 'You started. That was the hardest part.';
      });
    }
  }

  Future<void> _addToPlan() async {
    final state = AppScope.of(context);
    final iso = isoDate(state.clock());
    for (final (text, _) in _steps) {
      state.data.plans.steps.add(Step(text: text, day: iso, added: iso));
    }
    await state.save();
    if (mounted) setState(() => _added = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Help me start')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        // a question that came late, after the split (B-19), shows here; before the split it shows above its button
        if (_running case final i?) ...[
          Text('Step ${i + 1} of ${_steps.length}', style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(_steps[i].$1, key: const Key('help_running_step'), style: voiceStyle(context, size: 28)),
          const SizedBox(height: 28),
          Center(child: SizedBox(width: 220, height: 220, child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(value: _left / _total, strokeWidth: 10, strokeCap: StrokeCap.round,
                backgroundColor: scheme.outlineVariant),
            Center(child: Text('${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}',
                style: t.displaySmall?.copyWith(fontFamily: t.bodyMedium?.fontFamily, fontFeatures: const [FontFeature.tabularFigures()]))),
          ]))),
          const SizedBox(height: 28),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton(key: const Key('help_done'), onPressed: _next,
                child: Text(i + 1 < _steps.length ? 'Done, next step' : 'Done')),
            TextButton(onPressed: () {
              _timer?.cancel();
              setState(() => _running = null);
            }, child: const Text('Stop for now')),
            TextButton.icon(onPressed: () => parkThought(context), icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Park a thought')),
          ]),
        ] else ...[
          if (_steps.isEmpty) ...[
            const Text('Name the thing you keep putting off. I will split it into small steps, and the first one takes '
                'about two minutes.'),
            const SizedBox(height: 16),
            TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.long, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('help_task'), controller: _task, minLines: 1, maxLines: 3,
                decoration: const InputDecoration(hintText: 'For example: reply to the email from the landlord')),
            const SizedBox(height: 12),
            FilledButton.icon(key: const Key('help_split'), onPressed: _busy ? null : _split,
                icon: const Icon(Icons.auto_awesome_outlined), label: Text(_busy ? 'Splitting...' : 'Split it for me')),
          ] else ...[
            Text(_task.text.trim(), style: voiceStyle(context, size: 24)),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              for (final (i, (text, min)) in _steps.indexed)
                ListTile(leading: CircleAvatar(radius: 14, child: Text('${i + 1}')), title: Text(text),
                    trailing: Text('$min min', style: t.bodySmall)),
            ])),
            const SizedBox(height: 16),
            FilledButton.icon(key: const Key('help_start'), onPressed: () => _start(0),
                icon: const Icon(Icons.play_arrow), label: const Text('Start the first step together')),
            const SizedBox(height: 4),
            TextButton(onPressed: _added ? null : _addToPlan,
                child: Text(_added ? "Added to today's plan" : "Add these to today's plan")),
          ],
        ],
        if (_message != null) ...[const SizedBox(height: 16), Text(_message!, style: t.bodyMedium)],
        if (_support)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(key: const Key('help_support'),
              onPressed: () => showCrisisSheet(context), icon: const Icon(Icons.favorite_outline),
              label: const Text('Support'))),
      ])),
    );
  }
}
