// The model behind the therapist. The real runtime (llama.cpp on the device, running the trained GGUF file) plugs in
// behind this interface; until it exists, StandInModel lets every screen and flow be built and tested. The stand-in
// is clearly labelled in the app and gives no therapy: it only exercises the session flow.

abstract class ModelRuntime {
  /// Generate the next reply for messages in the training format (system, user, assistant ...), word by word.
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220});

  /// A human-readable name shown in Settings, so it is always clear which model is answering.
  String get name;
}

/// A model that cannot answer just now, with what to tell the person instead (Solace Home: a home server that cannot be
/// reached, core/home_link.dart HomeLinkError). The session still says "I lost my place" and adds [sayToPerson] as a
/// quiet line under it (core/session.dart).
abstract class ModelUnavailable implements Exception {
  String get sayToPerson;

  /// Whether asking again may work (the reply was cut off, or the server could not be reached just now): the chat
  /// then offers Try again under the line (core/session.dart retryReply). Not for a refusal asking again cannot fix.
  bool get offerRetry;
}

/// A runtime whose words may be written on another computer (Solace Home's home server), so the screens say where a
/// piece of writing was made (H19-05: the weekly letter said "written on this device" when the server wrote it).
abstract class WritesElsewhere {
  /// Whether the next words are expected from the home server (it is paired and was not found down a moment ago).
  bool get writesOnServer;

  /// Whether the last reply came from the home server (false: the model on this device answered instead).
  bool get lastOnServer;
}

/// A runtime that can read the start of a conversation ahead of time, so a later request that begins the same way
/// reads only what follows: the session's prompt (about 2,000 tokens) is read while the person fills in the check-in,
/// so the first reply reads only the check-in (2026-11-13: on an M2 E4B reads about 420 tokens a second).
abstract class PromptPreparer {
  Future<void> prepare(List<Map<String, String>> messages);
}

/// A runtime holding something to let go of when another takes its place (Unpair, Stop using it, Delete everything):
/// llama.cpp's engine, or the Home link with the model on this device it fell back to.
abstract class ReleasableRuntime {
  Future<void> release();
}

/// A runtime that can stop the reply it is writing at once (the chat's Stop, core/session.dart stopReply): without it a
/// stop still ends the reply on screen at once, and the runtime finishes its current sentence unseen.
abstract class ReplyCanceller {
  void cancelReply();
}

/// Whether [messages] ends with the app's request for the session note, and for the updated record: the two things
/// the model writes after a session. Stand-in models (this one, and the tests') tell them from a reply by this, never
/// by a token limit (2026-11-19: a reply's ceiling rose to 1,200 and tests that read "500 or more means the note"
/// held every reply back).
bool asksForNote(List<Map<String, String>> messages) =>
    (messages.last['content'] ?? '').startsWith('The session has ended. Write the session note');
bool asksForRecord(List<Map<String, String>> messages) => (messages.last['content'] ?? '').startsWith('Update the person');

class StandInModel implements ModelRuntime {
  const StandInModel();

  @override
  String get name => 'Stand-in (the trained model is not added yet)';

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final last = messages.last['content'] ?? '';
    final system = messages.first['content'] ?? '';
    final String reply;
    if (asksForNote(messages)) {
      final date = RegExp(r'Session: [^,]+, (.+)').firstMatch(last)?.group(1) ?? '';
      final kind = RegExp(r'Session: ([^,]+),').firstMatch(last)?.group(1) ?? 'session';
      reply = 'Session: $kind, $date\nTalked about: a test conversation with the stand-in model\n'
          'Practised: nothing yet (stand-in)\nMood: start not asked, end not asked\nHomework agreed: none\n'
          'Follow up next time: nothing\nPlan steps: none\nHabits: none\nGoals: none\nValues: none\n'
          'Vision board: none\nSafety: no concerns';
    } else if (asksForRecord(messages)) {
      // the record as it stands, under either prompt's heading for it ("Therapy record" since v5)
      final story = RegExp(r'(?:Story so far|Therapy record):\n([\s\S]*?)\n\nQuestionnaire').firstMatch(system)?.group(1) ?? '';
      reply = story.split('\n').where((l) => !l.startsWith('Goals they') && !l.startsWith('Values they')).join('\n');
    } else if (last.startsWith('[The person opened')) {  // with or without the check-in
      final homework = RegExp(r'Homework due: (.+)').firstMatch(system)?.group(1) ?? 'none';
      reply = homework == 'none'
          ? "Hello. I'm the stand-in model, here so the app can be tested. How are you today?"
          : "Hello again. Last time you planned: $homework. How did it go?";
    } else {
      reply = "Thank you for telling me. (Stand-in reply: the trained model will answer here.)";
    }
    for (final w in reply.split(' ')) {
      yield '$w ';
    }
  }
}
