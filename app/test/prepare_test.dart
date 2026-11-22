// The session's prompt is read while the check-in screen is open (core/session.dart prepare): what is prepared must
// be exactly the start of what the session's first request sends, or the model's prefix reuse finds nothing to reuse.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

/// Keeps what it is asked to prepare and every request after it.
class PreparingModel extends StandInModel implements PromptPreparer {
  final prepared = <List<Map<String, String>>>[];
  final requests = <List<Map<String, String>>>[];
  @override
  Future<void> prepare(List<Map<String, String>> messages) async => prepared.add(messages);
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    requests.add(messages);
    yield "It's good to see you. What has been on your mind?";
  }
}

void main() {
  test('the prepared prompt is the start of the first request, check-in and practice included', () async {
    for (final practice in ['', 'Letting thoughts pass']) {
      final model = PreparingModel();
      SessionController controller() => SessionController(model: model,
          prompts: const Prompts(system: '{mode_line}\n{session_line}\n{memory_block}', note: '', story: ''),
          data: AppData(), vault: MemoryVault(), clock: () => DateTime(2026, 11, 13, 9));
      controller().prepare('daily_checkin', practiceName: practice);
      await controller().start('daily_checkin', practiceName: practice, checkIn: const CheckIn(mood: 4, safety: 'fine'));
      final ready = model.prepared.single, first = model.requests.first;
      expect(ready.first, first.first, reason: 'the same system prompt');
      expect(first[1]['content'], startsWith(ready[1]['content']!.substring(0, ready[1]['content']!.length - 1)),
          reason: 'the open event with the check-in begins as the prepared one does');
      expect(first[1]['content'], contains('mood 4 out of 10'));
    }
  });

  test('a runtime that cannot prepare is left alone', () {
    SessionController(model: const StandInModel(), prompts: const Prompts(system: '', note: '', story: ''),
        data: AppData(), vault: MemoryVault()).prepare('daily_checkin');
  });
}
