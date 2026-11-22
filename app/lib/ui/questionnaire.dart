// One questionnaire at a time, one question per screen. PHQ-9 question 9 above zero opens the support screen.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/questionnaires.dart';
import 'crisis.dart';
import 'premium.dart';

class QuestionnaireFlow extends StatefulWidget {
  const QuestionnaireFlow({super.key, required this.list});
  final List<Questionnaire> list;
  @override
  State<QuestionnaireFlow> createState() => _QuestionnaireFlowState();
}

class _QuestionnaireFlowState extends State<QuestionnaireFlow> {
  int _q = 0;
  int _i = 0;
  final List<int> _answers = [];
  bool _busy = false; // an answer is being handled (round 5 review, D-08)
  bool _crisisNoted = false; // this questionnaire's alert item has been recorded as a crisis already (D-07)

  Questionnaire get _cur => widget.list[_q];

  /// Round 5 review, D-08: a double tap on the last answer saved the questionnaire twice (the second record with one
  /// answer too many) and its second pop closed the screen beneath. A tap while an answer is being handled, or once
  /// every question has its answer, does nothing: one save, one pop.
  Future<void> _pick(int score) async {
    if (_busy || _answers.length >= _cur.items.length) return;
    _busy = true;
    try {
      await _answer(score);
    } finally {
      _busy = false;
    }
  }

  Future<void> _answer(int score) async {
    final state = AppScope.of(context);
    _answers.add(score);
    final last = _answers.length == _cur.items.length;
    final alert = _cur.alertItem == _i && score > 0;
    // Round 5 review, D-07: the crisis (its record and the 7-day watch) and the answers are recorded BEFORE the
    // support sheet opens, as the check-in's "Yes" is (round 4 review, B-08); before, they were kept only after the
    // sheet closed. Round 9 review B, 9B-02: their save starts then too but is not waited for, so the sheet opens at
    // once however long the store takes to write, and the save finishes while it shows.
    if (last) {
      final saving = state.saveScores(_cur, List.of(_answers), crisisNoted: _crisisNoted);
      if (alert) {
        unawaited(saving);
      } else {
        await saving;
      }
    } else if (alert) {
      state.noteCrisis(alertReason(_cur));
      _crisisNoted = true;
      unawaited(state.save());
    }
    if (!mounted) return;
    if (alert) {
      await showCrisisSheet(context, flagged: true);
      if (!mounted) return;
    }
    if (!last) {
      setState(() => _i++);
      return;
    }
    if (_q + 1 < widget.list.length) {
      setState(() {
        _q++;
        _i = 0;
        _answers.clear();
        _crisisNoted = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: BarTitle(_cur.title)),
      body: Readable(maxWidth: 720, child: FillOrScroll(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LinearProgressIndicator(value: _i / _cur.items.length, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 20),
        Text(_cur.stem, style: t.bodyLarge),
        const SizedBox(height: 16),
        Text(_cur.items[_i], style: t.headlineSmall),
        const SizedBox(height: 24),
        for (var s = 0; s < _cur.options.length; s++) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(onPressed: () => _pick(s), style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)), child: Text(_cur.options[s]))),
        const Spacer(),
        Text('Question ${_i + 1} of ${_cur.items.length}', textAlign: TextAlign.center, style: t.bodySmall),
      ]))),
    );
  }
}
