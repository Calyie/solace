// Round 6 review E, E-02 (the proof failed on 4a8da11 and passes since the round 6 fix; the control passes): Settings > Space
// Solace uses > "Delete older conversations" deletes the conversations only. The person's words quoted from them in
// steps, habits, goals, values, vision-board items and noticed things stay, and so do the last note and next step when
// they are a deleted conversation's own (they go to the model at the next session). Round 5's C-11 fix
// (AppData.deleteSessions) is used by Choose what to delete only; this second way to delete conversations was left
// out, and its confirmation says "Their words and notes are deleted from this device".
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/storage.dart';
import 'package:solace/core/store.dart';

void main() {
  AppData data() {
    final d = AppData()
      ..lastNote = 'note of the old conversation'
      ..homeworkDue = 'call my sister';
    d.sessions.add(SessionRecord(date: '2026-03-02', kind: 'daily_checkin', note: 'note of the old conversation',
        turns: [('person', 'Honesty matters to me more than anything. I will call my sister on Sunday.')]));
    d.plans.values.add(Value(text: 'Honesty', quote: 'Honesty matters to me', added: '2026-03-02'));
    d.plans.steps.add(Step(text: 'Call my sister', quote: 'call my sister on Sunday', added: '2026-03-02'));
    d.suggestions.add(PendingSuggestion('value', 'Family', 'call my sister', '2026-03-02'));
    return d;
  }

  test('control: Choose what to delete takes the quoted words and the note (C-11)', () {
    final d = data();
    d.deleteSessions({d.sessions.single});
    expect(d.plans.values.single.quote, '');
    expect(d.plans.steps.single.quote, '');
    expect(d.suggestions.single.quote, '');
    expect(d.lastNote, '');
  });

  test('E-02: "Delete older conversations" takes their quoted words and their note too', () {
    final d = data();
    final removed = deleteConversationsBefore(d, DateTime(2026, 9, 15)); // older than six months, on 15 November
    expect(removed, 1);
    expect(d.sessions, isEmpty);
    expect(d.plans.values.single.quote, '', reason: 'the deleted conversation\'s words are still kept in a value');
    expect(d.plans.steps.single.quote, '', reason: '...and in a step');
    expect(d.suggestions.single.quote, '', reason: '...and in a noticed thing');
    expect(d.memoryFor(DateTime(2026, 11, 15)).lastNote, '',
        reason: 'the deleted conversation\'s note still opens the next session');
  });
}
