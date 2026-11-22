// Safety layer 2 on the device (STATUS T4): the released classifier (mmBERT-base, int8 ONNX, runs/safety_v5_base_s9)
// reads the person's message with the therapist's last words, and alarms when the probability of any risk
// (1 - p(safe)) reaches the threshold set on this same int8 file (safety_v5a_s9: 4.41e-6; held-out everyday alarms at
// most 0.25 percent, 74 of 75 crisis messages caught on the final check). It runs after the phrase rules, which stay
// first; a classifier alarm opens the crisis response like a rule alarm.
//
// For the try-out build the files sit in the app's documents folder beside a .sha256 list, like the model: the 641 MB
// file is checked once by SHA-256 (remembered by size and date), and a file that does not match is not used, in which
// case Settings says so and the phrase rules alone remain. The size cut (STATUS) will bundle it in the app instead.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'bpe_tokenizer.dart';
import 'llama_model.dart' show ModelFile;
import 'trusted.dart';

/// The risk of one message from the classifier's outputs, one list of logits per window (labels: safe first): the
/// highest window's probability of any risk, computed in double precision as tests/make_safety_fixtures.py does.
/// A window whose outputs are not finite numbers (a faulty model) is a risk of 1, an alarm, never a pass
/// (verification round 2: NaN went through math.max, and NaN >= threshold is false).
double riskOf(List<List<double>> windowLogits) {
  var risk = 0.0;
  for (final l in windowLogits) {
    if (l.isEmpty || l.any((x) => !x.isFinite)) return 1.0;
    final top = l.reduce(math.max);
    final e = [for (final x in l) math.exp(x - top)];
    final sum = e.reduce((a, b) => a + b);
    final r = 1 - e[0] / sum;
    if (!r.isFinite) return 1.0;
    risk = math.max(risk, r);
  }
  return risk;
}

/// The most the classifier reads of one message (OWASP review 2026-11-14, OW-A06-2): its last 12,000 characters, the
/// most a text box takes (core/session.dart maxInput), where a long paste ends. Every caller passes through here, so
/// no path can hand it unbounded text; the phrase rules still read the whole message. A cut never splits a character
/// in two.
const classifierMaxChars = 12000;

String forClassifier(String text, [int max = classifierMaxChars]) {
  if (text.length <= max) return text;
  var from = text.length - max;
  final first = text.codeUnitAt(from);
  if (first >= 0xDC00 && first <= 0xDFFF) from++; // the second half of a pair whose first half was cut off
  return text.substring(from);
}

class SafetyClassifier {
  SafetyClassifier._(this._session, this._tok, this.threshold, this._maxLen, this._contextChars);

  final OrtSession _session;
  final BpeWorker _tok; // tokenises in its own isolate, never on the screen's (OW-A06-2)
  final double threshold;
  final int _maxLen, _contextChars;

  /// The classifier in [dir] (safety.int8.onnx, tokenizer.json, labels.json and a .sha256 list naming the ONNX file),
  /// or null when it is absent or fails its check; [report] says which, for Settings.
  ///
  /// [native] runs the native load (the tokenizer worker and the ONNX session) once the files are checked: main.dart
  /// passes the load marker (core/load_guard.dart), so the checksum of the 641 MB file is never inside it (round 9
  /// review B, 9B-09: a start ended during that long check left a marker as if the load had crashed).
  static Future<SafetyClassifier?> load(Directory dir, File checkCache, void Function(String) report,
      {Future<SafetyClassifier> Function(Future<SafetyClassifier> Function() open)? native}) async {
    final onnx = File('${dir.path}/safety.int8.onnx');
    final tokFile = File('${dir.path}/tokenizer.json');
    final labelsFile = File('${dir.path}/labels.json');
    if (!await onnx.exists() || !await tokFile.exists() || !await labelsFile.exists()) return null;
    // every file the classifier reads must match the checksums built into this version of Solace (core/trusted.dart):
    // a swapped model, tokenizer or threshold file would weaken the safety layer without a sign (security review
    // 2026-11-14, SC-1 and F-04); the threshold itself is a constant, not read from the file
    report('Checking the safety classifier...');
    if (!await ModelFile(onnx, trustedSafety['safety.int8.onnx']!).verify(checkCache)
        || await sha256Of(tokFile) != trustedSafety['tokenizer.json']
        || await sha256Of(labelsFile) != trustedSafety['labels.json']) {
      report('The safety classifier files are not the ones this version of Solace was built with, so the classifier is '
          'off; the phrase rules still check every message. Add the voice and safety bundle again in Settings.');
      return null;
    }
    Future<SafetyClassifier> open() async {
      final tok = await BpeWorker.spawn(tokFile.path);
      final OrtSession session;
      try {
        session = await OnnxRuntime().createSession(onnx.path,
            options: OrtSessionOptions(providers: [OrtProvider.CPU], intraOpNumThreads: 2));
      } catch (_) {
        tok.close();
        rethrow;
      }
      return SafetyClassifier._(session, tok, classifierThreshold, classifierMaxLen, classifierContextChars);
    }

    final clf = await (native == null ? open() : native(open));
    report('Safety classifier ready.');
    return clf;
  }

  /// The probability of any risk in [text] (its last [classifierMaxChars] characters), read with the therapist's last
  /// words [context]. Only the end of the context is sent to the worker: twice [_contextChars] UTF-16 units always
  /// hold the [_contextChars] characters the windows keep.
  Future<double> risk(String context, String text) async {
    final logits = <List<double>>[];
    final ctx = forClassifier(context, 2 * _contextChars);
    for (final w in await _tok.windows(ctx, forClassifier(text), maxLen: _maxLen, contextChars: _contextChars)) {
      final ids = await OrtValue.fromList(Int64List.fromList(w), [1, w.length]);
      final mask = await OrtValue.fromList(Int64List.fromList(List.filled(w.length, 1)), [1, w.length]);
      try {
        final out = await _session.run({'input_ids': ids, 'attention_mask': mask});
        final values = await out.values.first.asFlattenedList();
        logits.add([for (final v in values) (v as num).toDouble()]);
        for (final o in out.values) {
          await o.dispose();
        }
      } finally {
        await ids.dispose();
        await mask.dispose();
      }
    }
    return riskOf(logits);
  }

  /// True when the risk reaches the threshold, or is not a number at all (fails closed, never open).
  Future<bool> alarm(String context, String text) async {
    final r = await risk(context, text);
    return !r.isFinite || r >= threshold;
  }

  Future<void> close() {
    _tok.close();
    return _session.close();
  }
}
