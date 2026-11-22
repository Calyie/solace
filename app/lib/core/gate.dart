// The gate in front of spoken reliving (imaginal exposure). Enforced here in code, not left to the model: the session
// controller refuses to open a reliving session unless this gate is open. Each reason it stays closed is listed so
// the app can explain it kindly and offer the written approach or stabilising work instead.
import 'store.dart';

class ReadinessAnswers {
  const ReadinessAnswers({
    required this.practisedGrounding,
    required this.noSuicidalThoughtsOrRecentSelfHarm,
    required this.notLivingWithTheDanger,
    required this.noPsychosis,
    required this.rarelyLoseTouchWithSurroundings,
    required this.supportPersonPresent,
  });
  final bool practisedGrounding;
  final bool noSuicidalThoughtsOrRecentSelfHarm;
  final bool notLivingWithTheDanger;
  final bool noPsychosis;
  final bool rarelyLoseTouchWithSurroundings;
  final bool supportPersonPresent;
}

class GateResult {
  const GateResult(this.reasons);
  final List<String> reasons;
  bool get open => reasons.isEmpty;
}

GateResult relivingGate(AppData data, ReadinessAnswers a, DateTime now) {
  final reasons = <String>[];
  if (data.settings.mode != 'full') reasons.add('Deep work mode is off.');
  if (!a.practisedGrounding) reasons.add('Grounding needs practising first, so you have a way back to the present.');
  if (!a.noSuicidalThoughtsOrRecentSelfHarm) {
    reasons.add('With thoughts of suicide or recent self-harm, stabilising work comes first.');
  }
  if (!a.notLivingWithTheDanger) reasons.add('While the danger is still part of your life, safety comes first.');
  if (!a.noPsychosis) reasons.add('With experiences like hearing or seeing things others do not, this needs a clinician.');
  if (!a.rarelyLoseTouchWithSurroundings) {
    reasons.add('Losing touch with your surroundings often means grounding work comes first.');
  }
  if (!a.supportPersonPresent) reasons.add('A support person needs to be with you for this session.');
  final cutoff = now.subtract(const Duration(days: 14));
  final recentCrisis = data.safetyEvents.any((e) =>
      e['level'] == 'crisis' && DateTime.tryParse(e['date'] as String? ?? '')?.isAfter(cutoff) == true);
  if (recentCrisis) reasons.add('A crisis was flagged in the last two weeks, so stabilising work comes first.');
  return GateResult(reasons);
}
