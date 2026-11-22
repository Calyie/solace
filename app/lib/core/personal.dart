// Personal words for meditations, filled in without asking anything. Only sources that read correctly when spoken
// to the person are used: their values and goals (from their sessions, editable), today's focus (their latest commitment or homework),
// and the optional "words for your meditations" in Settings. The story so far is written about the person in the
// third person ("her sister"), so it is never spoken back as it is. Every field has a gentle default.
import 'dates.dart';
import 'store.dart';

String _short(String s, {int words = 14}) {
  final first = s.split(RegExp(r'[.;\n]')).first.trim().replaceAll(RegExp(r'''^["'“‘]+|["'”’]+$'''), '');
  final w = first.split(RegExp(r'\s+'));
  return w.length <= words ? first : w.take(words).join(' ');
}

Map<String, String> personalWords(AppData d, DateTime now) {
  final out = <String, String>{};
  if (d.plans.values.isNotEmpty) out['value'] = d.plans.values.first.text;
  if (d.plans.goals.isNotEmpty) out['goal'] = _short(d.plans.goals.first.text);
  final today = isoDate(now);
  final commitments = [
    for (final p in d.programmes)
      for (final (date, e) in p.log)
        if (e.type == 'commitment' && date == today) e.text,
  ];
  if (commitments.isNotEmpty) {
    out['today_focus'] = _short(commitments.last);
  } else if (d.homeworkDue.isNotEmpty) {
    out['today_focus'] = _short(d.homeworkDue);
  }
  final w = d.settings.words;
  for (final k in ['kind_phrase', 'calm_word', 'intention', 'good_moment', 'struggle']) {
    if ((w[k] ?? '').trim().isNotEmpty) out[k] = w[k]!.trim();
  }
  return out;
}

/// Replace {slot|default} with the person's words, or the default when there are none.
String fillPersonal(String text, Map<String, String> words) =>
    text.replaceAllMapped(RegExp(r'\{(\w+)\|([^}]*)\}'), (m) => words[m.group(1)] ?? m.group(2)!);
