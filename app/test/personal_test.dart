// Meditations are personalised without asking anything, and only with words that read correctly when spoken to
// the person; the third-person story is never read back.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/personal.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/store.dart';

void main() {
  final now = DateTime(2026, 11, 26, 7, 30);

  test('defaults are used when nothing is known', () {
    final words = personalWords(AppData(), now);
    expect(fillPersonal('Today, let this guide you: {value|what matters most to you}.', words),
        'Today, let this guide you: what matters most to you.');
  });

  test('approved values, today\'s commitment and chosen words are used', () {
    final d = AppData()
      ..plans = Plans(values: [Value(text: 'creativity')], goals: [Goal(text: 'Hand in drawings on time')])
      ..homeworkDue = 'a ten-minute walk after lunch'
      ..settings.words['calm_word'] = 'harbour'
      ..programmes.add(Programme('morning focus and purpose', '2026-11-20',
          log: [('2026-11-26', const LogEntry('commitment', 'write the first paragraph at 9:00', {}))]));
    final w = personalWords(d, now);
    expect(w['value'], 'creativity');
    expect(w['today_focus'], 'write the first paragraph at 9:00'); // today's commitment comes before homework
    expect(fillPersonal('say {calm_word|steady}', w), 'say harbour');
  });

  test('homework is today\'s focus when there is no commitment for today', () {
    final d = AppData()..homeworkDue = 'a ten-minute walk after lunch. Also call Leila.';
    expect(personalWords(d, now)['today_focus'], 'a ten-minute walk after lunch');
  });

  test('the third-person story is never spoken back', () {
    final d = AppData()..story = Story(sections: {
      'About': 'Amira, 29, lives alone with her cat.', 'What helps': 'Talking to her sister Leila.',
      'Beliefs we are working on': "'If my work isn't perfect, people will see I'm a fraud.'",
    });
    final w = personalWords(d, now);
    expect(w.values.any((v) => v.contains('her ')), isFalse);
    expect(w.containsKey('good_moment'), isFalse);
    expect(w.containsKey('struggle'), isFalse);
  });
}
