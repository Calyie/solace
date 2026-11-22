// Review round 7 B (H7-02): the two concern rules ('cannot go on', 'hurting myself') show the support line ("If things
// feel like too much, support is here any time.") on plainly safe sentences: being worn out by work, a course, pain or a
// baby's nights; wanting a quiet hour; an accident. On the 472,628 CACTUS client lines they fire 226 times, almost all
// on help-seeking ("I'm willing to try, I can't keep going like this") or a fear of an accident. In Help me start the
// same verdict opens the full support sheet (ui/help_me_start.dart _split). Hand-written lines, then two real CACTUS
// client lines. Every test asserts the safe behaviour, so each failed on c8e45c9; fixed in round 7 (fix/round7-safety).
import 'package:solace/core/store.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/formats.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const plainlySafe = [
  "I can't keep going at this pace at work, something has to give.",
  "I can't go on with this course, I think I'm going to drop out and do an apprenticeship.",
  "I can't go on like this with my back pain, I need to see a specialist.",
  "I can't keep going with these 12 hour shifts.",
  "I feel like I can't keep going like this with no sleep, the baby is up every hour.",
  'I just want to disappear for a bit and read my book.',
  "I'm hurting myself by staying up so late, I know.",
  "I'm scared I'll hurt myself on the ice, it's so slippery.",
  "Write my essay, I can't keep going with it", // a Help me start task: opens the full support sheet there
  "Yes, especially when I'm alone at home and thinking about all the places I can't go on my own.",
  "I tripped and fell. It wasn't anything major, but I hurt myself and had to cut the hike short.",
];

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  // fixed in round 7 (H7-02, owner 2026-11-15: nothing under 90 percent precision shows): a worry from the phrase
  // rules is recorded but shows nothing, so the proof now drives the session and checks what the person sees
  for (final l in plainlySafe) {
    test('H7-02: "$l" shows no support line', () async {
      final s = SessionController(model: const StandInModel(), prompts: prompts, data: AppData(), vault: MemoryVault(),
          clock: () => DateTime(2026, 11, 15, 9));
      await s.start('daily_checkin');
      await s.send(l);
      expect(s.lastSafety.level, SafetyLevel.none, reason: 'a support line would show');
      expect(s.crisisCards, isEmpty);
    });
  }
}
