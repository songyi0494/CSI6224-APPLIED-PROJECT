import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';

const recommendationReasonsUnavailable =
    'Confirmed supporting information is unavailable. View the detailed decision trace for the recorded evidence.';

/// Display only: never evaluates a recommendation or changes clinical actions.
/// Live traces have no input snapshot, so current facts need revision binding.
List<String> recommendationReasons(
  ClinicalCase assessment, {
  required int investigationRevision,
}) {
  final evaluation = assessment.evaluation;
  if (evaluation == null ||
      evaluation.actions.isEmpty ||
      !{'complete', 'action_taken'}.contains(evaluation.decision)) {
    return const [recommendationReasonsUnavailable];
  }
  final bound =
      evaluation.pathwayRevision != null &&
      evaluation.pathwayRevision == assessment.pathwayRevision &&
      evaluation.investigationRevision == investigationRevision;
  final reasons = <String>[];
  var unavailable = false;
  for (final trace in evaluation.trace) {
    if (trace.nodeType == 'leaf') continue;
    if (trace.nodeType != null && trace.nodeType != 'decision') {
      unavailable = true;
      continue;
    }
    final live = trace.nodeType == 'decision';
    // Legacy trace input is a saved snapshot. Do not fill its gaps from today.
    final facts = live
        ? (bound ? assessment.clinicianFacts : const <String, Object?>{})
        : trace.input;
    final reason = trace.matched == null ? null : _reason(trace, facts, live);
    if (reason != null) {
      if (!reasons.contains(reason)) reasons.add(reason);
    } else {
      unavailable = true;
    }
  }
  if (reasons.isEmpty) return const [recommendationReasonsUnavailable];
  if (unavailable) {
    reasons.add(
      'Some recorded checks lack confirmed supporting information. View the detailed decision trace.',
    );
  }
  return reasons;
}

String? _reason(ReasoningTraceEntry t, Map<String, Object?> f, bool live) {
  final matched = t.matched!;
  final pathway = live ? t.pathwayId : 'PATHWAY1';
  if (pathway != 'PATHWAY1' && pathway != 'PATHWAY2') return null;
  // Only known snapshot-era conditions have verified legacy match semantics.
  if (!live &&
      !{
        'RENAL_DYSFUNCTION',
        'ON_OSTEOPOROSIS_TREATMENT',
        'T_SCORE',
        'ADHERENCE_CONCERN',
        'RECENT_MAJOR_FRACTURES',
      }.contains(t.ruleId)) {
    return null;
  }
  if (live && t.ruleId == 'T_SCORE') return null;
  String? boolean(String key, String yes, String no) {
    final value = f[key];
    if (value is! bool || value != matched) return null;
    return value ? yes : no;
  }

  num? number(String key) =>
      f[key] is num && (f[key] as num).isFinite ? f[key] as num : null;
  if (pathway == 'PATHWAY2') {
    return switch (t.ruleId) {
      'ON_ANTIRESORPTIVE_TREATMENT' => boolean(
        'antiresorptiveTreatmentStatus',
        'Current antiresorptive treatment is recorded.',
        'No current antiresorptive treatment is recorded.',
      ),
      // The source question and field label disagree at exactly 12 months.
      // The stored boolean cannot resolve this; do not invent a duration.
      'ANTIRESORPTIVE_TREATMENT_DURATION' => boolean(
        'antiresorptiveTreatmentDuration',
        'The recorded antiresorptive treatment-duration criterion was met.',
        'The recorded antiresorptive treatment-duration criterion was not met.',
      ),
      'TREATMENT_ADHERENCE' => boolean(
        'adheredToTheTreatment',
        'Adherence to the treatment plan is recorded.',
        'Non-adherence to the treatment plan is recorded.',
      ),
      'SYMPTOMATIC_FRACTURE' => boolean(
        'symptomaticFractureInLast12M',
        'A symptomatic fracture in the last 12 months is recorded.',
        'No symptomatic fracture in the last 12 months is recorded.',
      ),
      'MULTIPLE_FRACTURES' => boolean(
        'multipleFractures',
        'Two or more fractures are recorded.',
        'Two or more fractures are not recorded.',
      ),
      'CHECK_BMD' => boolean(
        'lowBMD',
        'A BMD T-score below -3.0 at at least one site is recorded.',
        'A BMD T-score below -3.0 at any site is not recorded.',
      ),
      'MI_OR_STROKE_HISTORY' => boolean(
        'priorMIorStroke',
        'A history of myocardial infarction or stroke is recorded.',
        'No history of myocardial infarction or stroke is recorded.',
      ),
      'SEQUENCING_WITH_HISTORY' || 'SEQUENCING_NO_HISTORY' => boolean(
        'sequencingFromDenosumab',
        'Transition from denosumab is recorded.',
        'Transition from denosumab is not recorded.',
      ),
      _ => null,
    };
  }
  switch (t.ruleId) {
    case 'RENAL_DYSFUNCTION':
      final value = number('eGFR');
      if (value == null || (live ? value >= 30 : value < 30) != matched) {
        return null;
      }
      return 'Recorded eGFR is $value mL/min (${value >= 30 ? 'at or above' : 'below'} 30 mL/min).';
    case 'ON_OSTEOPOROSIS_TREATMENT':
      return boolean(
        'osteoporosisTreatmentStatus',
        live
            ? 'Current osteoporosis treatment is recorded.'
            : 'Current or previous osteoporosis treatment is recorded.',
        live
            ? 'No current osteoporosis treatment is recorded.'
            : 'No current or previous osteoporosis treatment is recorded.',
      );
    case 'DXA_SCAN_AVAILABILITY':
      return boolean(
        'testAvailability',
        'DXA is recorded as available for this assessment.',
        'DXA is recorded as unavailable for this assessment.',
      );
    case 'RECENT_MAJOR_FRACTURES':
      return boolean(
        'hipVertebralOrMultipleFracturesInLast24M',
        'A hip fracture, vertebral fracture, or fractures at two or more sites in the last 24 months are recorded.',
        'No hip fracture, vertebral fracture, or fractures at two or more sites in the last 24 months are recorded.',
      );
    case 'T_SCORE_CHECK':
    case 'T_SCORE':
      final keys = live
          ? const ['femoralNeckTscore', 'hipTscore', 'lumbarSpineTscore']
          : const ['T-score'];
      final values = {
        for (final key in keys)
          if (number(key) != null) key: number(key)!,
      };
      final low = values.values.any((v) => v <= -2.5);
      if ((live ? low : !low) != matched ||
          (!low && values.length != keys.length) ||
          values.isEmpty) {
        return null;
      }
      const labels = {
        'femoralNeckTscore': 'femoral neck',
        'hipTscore': 'hip',
        'lumbarSpineTscore': 'lumbar spine',
        'T-score': 'recorded site',
      };
      final displayed = values.entries
          .map((e) => '${labels[e.key]} ${e.value}')
          .join('; ');
      return 'Recorded T-scores: $displayed. ${low
          ? 'At least one is at or below -2.5'
          : live
          ? 'All three are above -2.5'
          : 'The recorded value is above -2.5'}.';
    case 'ADHERENCE_CONCERN':
      final poor = f['knownPoorMedicationAdherence'];
      final cognition = f['cognitiveImpairment'];
      if (poor is! bool ||
          cognition is! bool ||
          (poor || cognition) != matched) {
        return null;
      }
      return matched
          ? '${[if (poor) 'Poor medication adherence', if (cognition) 'Cognitive impairment affecting adherence'].join(' and ')} ${poor && cognition ? 'are' : 'is'} recorded.'
          : 'Neither poor medication adherence nor cognitive impairment affecting adherence is recorded.';
    case 'RESIDENTIAL_OR_FRAILTY':
      final residential = f['liveInResidentialCare'];
      final frailty = number('clinicalFrailtyScore');
      final expectancy = number('lifeExpectancy');
      if (residential is! bool ||
          frailty == null ||
          expectancy == null ||
          (residential || frailty >= 6 || expectancy < 7) != matched) {
        return null;
      }
      return 'Residential care: ${residential ? 'yes' : 'no'}; frailty score: $frailty; life expectancy: $expectancy years. The recorded care-setting criterion ${matched ? 'was met' : 'was not met'} (residential care, frailty score at least 6, or life expectancy below 7 years).';
    case 'HIGH_RISK_CHECK':
      // Do not infer which subcondition caused a composite result. Display the
      // recorded outcome only when every supporting field is available.
      final numericKeys = [
        'femoralNeckTscore',
        'hipTscore',
        'lumbarSpineTscore',
        'FRAX10YmajorOsteoporoticFractureRiskPercent',
        'FRAX10YmajorHipFractureRiskPercent',
      ];
      final booleanKeys = [
        'recentFractureWithin2Y',
        'historyOf2orMoreFractures',
        'clinicalRiskFactors',
      ];
      if (numericKeys.any((k) => number(k) == null) ||
          booleanKeys.any((k) => f[k] is! bool)) {
        return null;
      }
      final low = numericKeys.take(3).any((k) => number(k)! <= -3.0);
      final risk =
          booleanKeys.any((k) => f[k] == true) ||
          number(numericKeys[3])! >= 30 ||
          number(numericKeys[4])! >= 4.5;
      if ((low && risk) != matched) return null;
      return 'The recorded very high fracture risk criterion ${matched ? 'was met' : 'was not met'}: a T-score at or below -3.0 together with a recorded fracture/risk factor or FRAX major fracture risk at least 30% or hip fracture risk at least 4.5%.';
    default:
      return null;
  }
}
