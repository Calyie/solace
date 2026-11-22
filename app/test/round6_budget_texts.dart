// Full boxes (12,000 characters) of ordinary text in several languages and forms, for the classifier's token budget
// (round 6 review F, F6-11). Shared by test/round6_classifier_budget_test.dart; not a test itself.
const _english = 'I have been feeling low for most of this week. Work has been heavy and I keep lying awake going over '
    'everything I said in the meeting on Tuesday. My sister rang on Sunday and I did not pick up, which I feel bad '
    'about now. I know the walks help, and I managed two of them, but the evenings are the hardest part. ';
const _polish = 'Przez większość tego tygodnia czułam się przygnębiona. W pracy jest ciężko i nie mogę zasnąć, bo w '
    'kółko myślę o tym, co powiedziałam na wtorkowym spotkaniu. Siostra dzwoniła w niedzielę, a ja nie odebrałam, i '
    'teraz jest mi z tym źle. Wiem, że spacery pomagają, udało mi się wyjść dwa razy, ale wieczory są najtrudniejsze. ';
const _greek = 'Όλη αυτή την εβδομάδα νιώθω πεσμένη. Η δουλειά είναι βαριά και μένω ξύπνια σκεπτόμενη ξανά και ξανά '
    'όσα είπα στη συνάντηση της Τρίτης. Η αδερφή μου τηλεφώνησε την Κυριακή και δεν το σήκωσα, και τώρα νιώθω άσχημα. '
    'Ξέρω ότι οι βόλτες βοηθούν, κατάφερα δύο, αλλά τα βράδια είναι το πιο δύσκολο κομμάτι. ';
const _russian = 'Почти всю эту неделю мне было тяжело. На работе много дел, и я не могу уснуть, снова и снова '
    'вспоминая, что я сказала на встрече во вторник. Сестра звонила в воскресенье, а я не ответила, и теперь мне '
    'стыдно. Я знаю, что прогулки помогают, мне удалось выйти дважды, но вечера даются тяжелее всего. ';
const _arabic = 'شعرت بالإحباط معظم هذا الأسبوع. العمل ثقيل وأبقى مستيقظة أفكر مرارا فيما قلته في اجتماع الثلاثاء. '
    'اتصلت أختي يوم الأحد ولم أرد، وأشعر بالذنب الآن. أعرف أن المشي يساعد، وتمكنت من الخروج مرتين، لكن المساء هو الأصعب. ';
const _hindi = 'इस पूरे हफ़्ते मैं उदास महसूस कर रही हूँ। काम बहुत भारी है और मैं रात भर जागकर मंगलवार की बैठक में कही '
    'हर बात के बारे में सोचती रहती हूँ। रविवार को बहन का फ़ोन आया और मैंने नहीं उठाया, अब मुझे बुरा लग रहा है। ';
const _emoji = 'today 😔😔 work 😩💼 again, sister called 📞❌ didn\'t answer 😞 walk 🚶‍♀️🌳 helped a bit 🙂 but night 🌙😢💔 '
    'can\'t sleep 😴❌🛏️ tired of it all 😮‍💨 ';
const _digits = '2026-11-01 07:30 mood 3/10 sleep 5.5h steps 4210 water 1.2l; 2026-11-02 08:10 mood 4/10 sleep 6.25h '
    'steps 6034 water 1.6l; 2026-11-03 06:55 mood 2/10 sleep 4.75h steps 1980 water 0.9l; ';
const _textSpeak = 'idk tbh im so done w everything rn, cant sleep again lol not lol, sis called didnt pick up ugh, '
    'walked 2x kinda helped but nights r the worst fr fr ';

String _box(String paragraph) {
  final b = StringBuffer();
  while (b.length < 12000) {
    b.write(paragraph);
  }
  return b.toString().substring(0, 12000);
}

/// Name -> a full box of it.
final fullBoxes = {
  'English prose': _box(_english),
  'Text speak': _box(_textSpeak),
  'Polish': _box(_polish),
  'Russian': _box(_russian),
  'Greek': _box(_greek),
  'Arabic': _box(_arabic),
  'Hindi': _box(_hindi),
  'Emoji': _box(_emoji),
  'Digits (mood log)': _box(_digits),
};
