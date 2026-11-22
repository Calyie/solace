// Standard questionnaires, free to use: PHQ-9 (depression) and GAD-7 (anxiety), released for free use by their
// authors; PCL-5 (post-traumatic stress), a US government work from the National Center for PTSD.
// Scores are kept by the app and shown to the model as "Monday 2 November: PHQ-9 12, GAD-7 11", as in training.

class Questionnaire {
  const Questionnaire({required this.name, required this.title, required this.stem, required this.items,
      required this.options, required this.bands, this.alertItem});
  final String name;
  final String title;
  final String stem;
  final List<String> items;
  final List<String> options; // the answer for score 0, 1, 2 ...
  final List<(int, String)> bands; // (lowest score, label), ascending
  final int? alertItem; // an item that opens the crisis screen if scored above zero

  int get maxScore => items.length * (options.length - 1);

  String band(int total) => bands.lastWhere((b) => total >= b.$1).$2;
}

/// Why a crisis was recorded when [q]'s alert item was answered above zero ("PHQ-9 item 9").
String alertReason(Questionnaire q) => '${q.name} item ${(q.alertItem ?? 0) + 1}';

const _often = ['Not at all', 'Several days', 'More than half the days', 'Nearly every day'];

const phq9 = Questionnaire(
  name: 'PHQ-9', title: 'Mood (PHQ-9)',
  stem: 'Over the last 2 weeks, how often have you been bothered by any of the following problems?',
  items: [
    'Little interest or pleasure in doing things',
    'Feeling down, depressed, or hopeless',
    'Trouble falling or staying asleep, or sleeping too much',
    'Feeling tired or having little energy',
    'Poor appetite or overeating',
    'Feeling bad about yourself, or that you are a failure or have let yourself or your family down',
    'Trouble concentrating on things, such as reading or watching television',
    'Moving or speaking so slowly that other people could have noticed, or the opposite: being so fidgety or '
        'restless that you have been moving around a lot more than usual',
    'Thoughts that you would be better off dead, or of hurting yourself in some way',
  ],
  options: _often,
  bands: [(0, 'minimal'), (5, 'mild'), (10, 'moderate'), (15, 'moderately severe'), (20, 'severe')],
  alertItem: 8,
);

const gad7 = Questionnaire(
  name: 'GAD-7', title: 'Anxiety (GAD-7)',
  stem: 'Over the last 2 weeks, how often have you been bothered by the following problems?',
  items: [
    'Feeling nervous, anxious, or on edge',
    'Not being able to stop or control worrying',
    'Worrying too much about different things',
    'Trouble relaxing',
    'Being so restless that it is hard to sit still',
    'Becoming easily annoyed or irritable',
    'Feeling afraid, as if something awful might happen',
  ],
  options: _often,
  bands: [(0, 'minimal'), (5, 'mild'), (10, 'moderate'), (15, 'severe')],
);

const pcl5 = Questionnaire(
  name: 'PCL-5', title: 'After a stressful experience (PCL-5)',
  stem: 'In the past month, how much were you bothered by:',
  items: [
    'Repeated, disturbing, and unwanted memories of the stressful experience',
    'Repeated, disturbing dreams of the stressful experience',
    'Suddenly feeling or acting as if the stressful experience were actually happening again',
    'Feeling very upset when something reminded you of the stressful experience',
    'Having strong physical reactions when something reminded you of it (heart pounding, trouble breathing, sweating)',
    'Avoiding memories, thoughts, or feelings related to the stressful experience',
    'Avoiding external reminders of it (people, places, conversations, activities, objects, or situations)',
    'Trouble remembering important parts of the stressful experience',
    'Having strong negative beliefs about yourself, other people, or the world',
    'Blaming yourself or someone else for the stressful experience or what happened after it',
    'Having strong negative feelings such as fear, horror, anger, guilt, or shame',
    'Loss of interest in activities that you used to enjoy',
    'Feeling distant or cut off from other people',
    'Trouble experiencing positive feelings',
    'Irritable behaviour, angry outbursts, or acting aggressively',
    'Taking too many risks or doing things that could cause you harm',
    'Being "superalert" or watchful or on guard',
    'Feeling jumpy or easily startled',
    'Having difficulty concentrating',
    'Trouble falling or staying asleep',
  ],
  options: ['Not at all', 'A little bit', 'Moderately', 'Quite a bit', 'Extremely'],
  bands: [(0, 'below the usual threshold'), (31, 'at or above the usual threshold for PTSD (31 to 33)')],
);

const questionnaires = [phq9, gad7, pcl5];
