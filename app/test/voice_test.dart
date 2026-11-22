// The parts of the voice that need no model (core/sherpa_voice.dart): how a reply is cut into spoken sentences, and
// the microphone's 16-bit samples as floats. Speaking and writing down run with the real models on the devices (T5).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/sherpa_voice.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/voice.dart';

void main() {
  // OWASP review 2026-11-14, OW-M2-2: the espeak-ng inside sherpa-onnx 1.13.8 lacked the fixes for CVE-2023-49990 to
  // 49994; since 2026-11-15 sherpa-onnx 2.0.1 has no espeak-ng at all, and text is still bounded by forSpeech and
  // capSentence before the engine reads it.
  group('OW-M2-2: what the speech engine is given', () {
    void bounded(List<String> sentences) {
      for (final s in sentences) {
        expect(s.length, inInclusiveRange(1, maxSpeechSentence), reason: s);
        for (final w in s.split(' ')) {
          expect(w.runes.length, lessThanOrEqualTo(maxSpeechWord), reason: w);
          expect(utf8.encode(w).length, lessThanOrEqualTo(maxSpeechWordBytes), reason: w);
        }
        expect(RegExp(r'[\p{Cc}\p{Cf}\p{So}\p{Sk}\p{Co}\p{Cs}]', unicode: true).hasMatch(s), isFalse, reason: s);
        expect(forSpeech(s), s, reason: 'made safe once is safe');
      }
    }

    test('hostile text comes out bounded, with nothing espeak does not need', () {
      final hostile = [
        'ing' * 20000, '${'ingingingly' * 5000}.', 'a' * 100000, 'Say this: ${'x' * 1000}!',
        'Ok\u0000\u0007\u001B[31m\u0085 then', 'Hello\u200B\u200C\u200D\u2060\uFEFFworld', '\u202Edlrow olleh\u202C',
        'I\u200F hear\u200E you', '😀😢💔 ${'🙂' * 3000} fine', 'z${'\u0301' * 500}algo', '\uD83D lone half \uDE00',
        ('word ' * 3000).trim(), '${'very ' * 200}long sentence without a full stop',
        '𝐀' * 500, '中' * 500, 'لا ${'ل' * 300}', List.filled(1000, '!').join(), '12345678901234567890' * 50,
        'Normal text, with "quotes", (brackets) and 50% of it - fine… really?',
      ];
      for (final h in hostile) {
        final out = speechSentences(h);
        bounded(out);
        // numbers are said as words since sherpa-onnx 2.x (each digit at most "seven " for one character and its space,
        // a run of more than 15 digits "a long number"): still linear in the input
        final bound = h.contains(RegExp(r'\d')) ? h.length * 4 : h.length + h.length ~/ maxSpeechWord + 1;
        expect(out.join(' ').length, lessThanOrEqualTo(bound), reason: h.substring(0, h.length < 20 ? h.length : 20));
        expect(out.join(' ').contains(RegExp(r'\d')), isFalse, reason: 'no digit reaches the lexicon-only engine');
      }
    });

    test('ordinary replies are spoken word for word', () {
      const reply = "That sounds like a hard week. What happened on Tuesday, when it started? It's okay to take "
          'your time; you can say "stop" whenever you like (I mean it) - 100% of the time. Café, naïve, déjà vu.';
      expect(forSpeech(reply), reply);
      // the one number is said as words (sherpa-onnx 2.x reads only lexicon words: OW-M2-2)
      expect(speechSentences(reply).join(' '), reply.replaceAll('100%', 'one hundred percent'));
    });

    test('a long word is cut, never dropped; a long sentence is cut at a space', () {
      expect(forSpeech('a' * 100), '${'a' * 40} ${'a' * 40} ${'a' * 20}');
      expect(forSpeech('${'é' * 70}!'), '${'é' * 40} ${'é' * 30}!'); // 2 bytes each: 80 bytes per piece
      expect(forSpeech('𝐀' * 31), '${'𝐀' * 30} 𝐀'); // 4 bytes each: 120 bytes
      final parts = capSentence('${'word ' * 100}end');
      expect(parts.length, 2);
      expect(parts.first.endsWith('word'), isTrue);
      expect(parts.join(' '), '${'word ' * 100}end');
      expect(forSpeech('z${'\u0301' * 10}'), 'z${'\u0301' * 3}');
    });
  });

  test('a reply is spoken sentence by sentence, short fragments joined', () {
    expect(splitSentences('That sounds like a hard week. What happened on Tuesday, when it started?'),
        ['That sounds like a hard week.', 'What happened on Tuesday, when it started?']);
    expect(splitSentences('Mm. Take your time.'), ['Mm. Take your time.']);
    expect(splitSentences('Breathe in... and out. Let your shoulders drop, slowly, as you breathe out.'),
        ['Breathe in... and out. Let your shoulders drop, slowly, as you breathe out.']);
    expect(splitSentences('No full stop at the end of this one'), ['No full stop at the end of this one']);
    expect(splitSentences('"You said it was a fraud." Is that still how it feels to you today?'),
        ['"You said it was a fraud."', 'Is that still how it feels to you today?']); // the quote stays with its sentence
    expect(splitSentences('  '), isEmpty);
  });

  test('16-bit microphone samples become floats', () {
    final b = ByteData(6)
      ..setInt16(0, 0, Endian.little)
      ..setInt16(2, 16384, Endian.little)
      ..setInt16(4, -32768, Endian.little);
    expect(pcm16ToFloat(b.buffer.asUint8List()), [0.0, 0.5, -1.0]);
  });

  test("the voices are the owner's blind-listen order, Bella the default, then the two male voices", () {
    expect(kokoroSpeakers, {'af_bella': 2, 'af_heart': 3, 'am_michael': 16, 'bm_george': 26});
    expect(voices.keys, ['af_bella', 'af_heart_slow', 'af_heart', 'am_michael', 'bm_george']);
    // every voice speaks through the speaker the listen named, and the men as the owner heard them
    for (final v in voices.keys) {
      expect(kokoroSpeakers.values, contains(deliveryFor(v).speaker), reason: v);
    }
    expect((deliveryFor('am_michael').speed, deliveryFor('am_michael').pause), (1.0, Duration.zero));
    expect(deliveryFor('bm_george').speaker, 26);
    expect(Settings.fromJson({'voice': 'bm_george'}).voice, 'bm_george');
    expect(defaultVoice, 'af_bella');
    expect(Settings().voice, 'af_bella');
    expect(Settings.fromJson({'voice': 'af_heart_slow'}).voice, 'af_heart_slow');
    expect(Settings.fromJson({'voice': 'bf_emma'}).voice, 'af_bella', reason: 'a dropped voice falls back to the default');
  });

  test('the unhurried voice is slower and pauses, longer after an empathic sentence; the others do not', () {
    expect((deliveryFor('af_heart_slow').speaker, deliveryFor('af_heart_slow').speed), (3, 0.92));
    expect(pauseAfter('af_heart_slow', 'That sounds really hard.'), const Duration(milliseconds: 900));
    expect(pauseAfter('af_heart_slow', "I'm so sorry."), const Duration(milliseconds: 900));
    expect(pauseAfter('af_heart_slow', 'What happened next?'), const Duration(milliseconds: 450));
    expect(pauseAfter('af_bella', 'That sounds really hard.'), Duration.zero);
    expect(deliveryFor('unknown').speaker, 2, reason: 'an unknown voice is spoken by the default');
  });
}
