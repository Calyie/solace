// The named-emotion check-in (report recommendation 21): an optional layer beside the 0 to 10 tap. The person picks
// where they are on an energy by pleasantness grid (How We Feel's mood meter, Apple's State of Mind), then one or more
// feeling words, then, if they like, what is affecting them and a short note. It fits the owner's preference for words
// over numbers (decisions log, 6 November). The words are plain British English, about thirty per quarter of the grid;
// no study compares pickers like this, so it rests on convergent practice, not trial evidence.

/// The four quarters of the grid: (id, title, a few example words).
const quadrants = <(String, String, String)>[
  ('high_unpleasant', 'High energy, unpleasant', 'like tense, worried or frustrated'),
  ('high_pleasant', 'High energy, pleasant', 'like excited, hopeful or proud'),
  ('low_unpleasant', 'Low energy, unpleasant', 'like tired, sad or lonely'),
  ('low_pleasant', 'Low energy, pleasant', 'like calm, content or relaxed'),
];

const quadrantIds = {'high_unpleasant', 'high_pleasant', 'low_unpleasant', 'low_pleasant'};

String quadrantTitle(String id) => quadrants.firstWhere((q) => q.$1 == id, orElse: () => quadrants.first).$2;

bool quadrantIsPleasant(String id) => id.endsWith('_pleasant') && !id.endsWith('_unpleasant');

/// The feeling words for each quarter, from milder to stronger as far as that makes sense.
const emotionWords = <String, List<String>>{
  'high_unpleasant': [
    'uneasy', 'tense', 'nervous', 'worried', 'anxious', 'stressed', 'restless', 'on edge', 'jittery', 'apprehensive',
    'pressured', 'overwhelmed', 'panicky', 'frightened', 'scared', 'shocked', 'rattled', 'annoyed', 'irritable',
    'frustrated', 'fed up', 'wound up', 'agitated', 'exasperated', 'defensive', 'angry', 'resentful', 'furious',
    'jealous', 'envious', 'embarrassed', 'ashamed', 'humiliated', 'disgusted',
  ],
  'high_pleasant': [
    'upbeat', 'cheerful', 'happy', 'lively', 'curious', 'playful', 'amused', 'eager', 'interested', 'focused',
    'motivated', 'determined', 'confident', 'brave', 'hopeful', 'optimistic', 'enthusiastic', 'energised', 'inspired',
    'proud', 'accomplished', 'empowered', 'surprised', 'delighted', 'joyful', 'excited', 'chuffed', 'buzzing',
    'thrilled', 'elated', 'alive',
  ],
  'low_unpleasant': [
    'tired', 'flat', 'low', 'down', 'glum', 'bored', 'sluggish', 'weary', 'worn out', 'drained', 'exhausted',
    'burnt out', 'unmotivated', 'apathetic', 'numb', 'empty', 'sad', 'disappointed', 'discouraged', 'insecure',
    'fragile', 'hurt', 'guilty', 'lonely', 'left out', 'ignored', 'isolated', 'withdrawn', 'homesick', 'lost',
    'helpless', 'hopeless', 'heartbroken', 'grieving', 'miserable',
  ],
  'low_pleasant': [
    'calm', 'relaxed', 'at ease', 'content', 'comfortable', 'cosy', 'mellow', 'chilled', 'carefree', 'peaceful',
    'serene', 'settled', 'grounded', 'centred', 'balanced', 'rested', 'safe', 'secure', 'relieved', 'satisfied',
    'fulfilled', 'thoughtful', 'reflective', 'patient', 'gentle', 'tender', 'grateful', 'thankful', 'loved', 'loving',
    'connected', 'accepted', 'understood',
  ],
};

/// Every word, with the quarter it belongs to.
final Map<String, String> quadrantOfWord = {
  for (final MapEntry(key: q, value: words) in emotionWords.entries)
    for (final w in words) w: q,
};

/// What might be affecting them: (id, what the person sees).
const affectingTags = <(String, String)>[
  ('work', 'Work'), ('family', 'Family'), ('friends', 'Friends'), ('partner', 'Partner'), ('health', 'Health'),
  ('sleep', 'Sleep'), ('exercise', 'Exercise'), ('money', 'Money'), ('weather', 'Weather'), ('news', 'News'),
  ('self', 'Myself'), ('other', 'Something else'),
];

const tagIds = {'work', 'family', 'friends', 'partner', 'health', 'sleep', 'exercise', 'money', 'weather', 'news',
  'self', 'other'};

String tagLabel(String id) => affectingTags.firstWhere((t) => t.$1 == id, orElse: () => (id, id)).$2;

// a long note (owner, 2026-11-14: room to unload what one feels; ui/premium.dart TextLimit.long)
const maxNoteLength = 20000;
const _maxWords = 12;
final _at = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$');

/// The time an entry was made, as the app writes it: local date and time to the minute ("2026-11-26T19:30").
String stampOf(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// One named-feeling check-in.
class EmotionEntry {
  EmotionEntry({required this.at, required this.quadrant, required List<String> words, List<String>? tags,
      this.note = ''})
      : words = List.unmodifiable(words),
        tags = List.unmodifiable(tags ?? const []);
  final String at; // local date and time, "2026-11-26T19:30"
  final String quadrant; // one of quadrantIds
  final List<String> words; // feeling words, at least one
  final List<String> tags; // what was affecting them, from tagIds
  final String note; // optional, at most maxNoteLength characters

  String get date => at.substring(0, 10);
  int get hour => int.parse(at.substring(11, 13));
  DateTime get time => DateTime.parse(at);

  Map<String, dynamic> toJson() => {'at': at, 'quadrant': quadrant, 'words': words, 'tags': tags, 'note': note};

  /// An entry from the saved file, or null when it is not one (a damaged or hand-edited file never stops the app
  /// from opening: that one entry is left out). Unknown tags are dropped; words are kept as written (a later version
  /// may add words), trimmed and at most twelve.
  static EmotionEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'], quadrant = raw['quadrant'], words = raw['words'], tags = raw['tags'], note = raw['note'];
    if (at is! String || !_at.hasMatch(at)) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null || stampOf(parsed) != at) return null; // a real date and time, not "2026-13-40T99:99"
    if (quadrant is! String || !quadrantIds.contains(quadrant)) return null;
    if (words is! List) return null;
    final kept = <String>{
      for (final w in words)
        if (w is String && w.trim().isNotEmpty && w.trim().length <= 40) w.trim(),
    }.take(_maxWords).toList();
    if (kept.isEmpty) return null;
    final keptTags = <String>{
      if (tags is List)
        for (final t in tags)
          if (t is String && tagIds.contains(t)) t,
    }.toList();
    final text = note is String ? note.trim() : '';
    return EmotionEntry(at: at, quadrant: quadrant, words: kept, tags: keptTags,
        note: text.length > maxNoteLength ? text.substring(0, maxNoteLength) : text);
  }
}
