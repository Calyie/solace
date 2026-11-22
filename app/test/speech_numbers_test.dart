// OW-M2-2: sherpa-onnx 2.x reads only lexicon words, so numbers are said as words before speaking (core/speech_numbers.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/sherpa_voice.dart';
import 'package:solace/core/speech_numbers.dart';

void main() {
  test('numbers become words a lexicon has', () {
    expect(spokenNumbers('Call 116 123 any time.'), 'Call one one six one two three any time.');
    expect(spokenNumbers('Samaritans: 116123'), 'Samaritans: one one six one two three');
    expect(spokenNumbers('I woke at 3am again.'), 'I woke at three a m again.');
    expect(spokenNumbers('Meet at 3:30pm or 10:05 a.m.'), 'Meet at three thirty p m or ten oh five a m');
    expect(spokenNumbers('Back by 7:00.'), "Back by seven o'clock.");
    expect(spokenNumbers('It went up 50% in 2024.'), 'It went up fifty percent in twenty twenty four.');
    expect(spokenNumbers('My 21st birthday, the 3rd time.'), 'My twenty first birthday, the third time.');
    expect(spokenNumbers('Rate it 6 out of 10, or 7.5.'), 'Rate it six out of ten, or seven point five.');
    expect(spokenNumbers('About 1,200 steps; 1999 and 2005.'), 'About one thousand two hundred steps; nineteen ninety nine and two thousand and five.');
    expect(spokenNumbers('No numbers here.'), 'No numbers here.');
  });

  test('number words', () {
    expect(numberWords(0), 'zero');
    expect(numberWords(42), 'forty two');
    expect(numberWords(105), 'one hundred and five');
    expect(numberWords(1005), 'one thousand and five');
    expect(numberWords(2000000), 'two million');
  });

  test('a long paste of digits stays linear and leaves no digit for the engine', () {
    final paste = List.filled(3000, '12345678901 3:15pm 45% 2nd').join(' ');
    final sw = Stopwatch()..start();
    final out = spokenNumbers(paste);
    expect(sw.elapsedMilliseconds, lessThan(2000));
    expect(out.contains(RegExp(r'\d')), isFalse);
  });

  test('speech sentences carry no digits', () {
    expect(speechSentences('Call 116 123. It is 3am.').join(' ').contains(RegExp(r'\d')), isFalse);
  });
}
