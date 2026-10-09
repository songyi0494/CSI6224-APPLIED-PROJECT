import '../models/clinical_result_contract.dart';
import '../models/pathway_evaluation.dart';

/// Wording for saved outcomes only. No facts, comparisons or routing are run here.
List<String> recommendationExplanation(PathwayEvaluation evaluation) {
  final lines = <({int priority, int order, String text})>[];
  for (var i = 0; i < evaluation.trace.length; i++) {
    final t = evaluation.trace[i];
    if (t.nodeType != 'decision' || t.matched == null) continue;
    // Older contracts remain in the technical trace; never relabel their outcome.
    if (!const [
      'songyi-p1p2-20261009-adherence',
      'songyi-p1p2-20261009-care',
      'songyi-p1p2-20261009-bmd',
      'songyi-p1p2-20261008',
    ].contains(t.contractVersion)) {
      continue;
    }
    if (t.ruleId == 'ADHERENCE_CONCERN' &&
        t.contractVersion != 'songyi-p1p2-20261009-adherence') {
      continue;
    }
    final item = _outcomes['${t.pathwayId}:${t.ruleId}'];
    if (item == null) continue;
    if (t.pathwayId == 'PATHWAY1' &&
        ['T_SCORE_CHECK', 'HIGH_RISK_CHECK'].contains(t.ruleId) &&
        !const [
          'songyi-p1p2-20261009-adherence',
          'songyi-p1p2-20261009-care',
          'songyi-p1p2-20261009-bmd',
        ].contains(t.contractVersion)) {
      continue;
    }
    if (t.ruleId == 'RESIDENTIAL_OR_FRAILTY' &&
        !const [
          'songyi-p1p2-20261009-adherence',
          'songyi-p1p2-20261009-care',
        ].contains(t.contractVersion)) {
      continue;
    }
    lines.add((
      priority: item.$1 + (t.pathwayId == evaluation.pathway ? 0 : 10),
      order: i,
      text: t.matched! ? item.$2 : item.$3,
    ));
  }
  // Select important outcomes, then retain the actual saved traversal order.
  lines.sort(
    (a, b) => a.priority != b.priority
        ? a.priority.compareTo(b.priority)
        : a.order.compareTo(b.order),
  );
  final selected = lines.take(6).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return selected.map((item) => item.text).toList(growable: false);
}

const _outcomes = <String, (int, String, String)>{
  'PATHWAY1:P1_DEMOGRAPHIC_ELIGIBILITY': (
    3,
    'The recorded demographic criteria are met.',
    'The recorded demographic criteria are not met.',
  ),
  'PATHWAY1:MINIMAL_TRAUMA_FRACTURE': (
    0,
    'Minimal-trauma-fracture criteria are met.',
    'Minimal-trauma-fracture criteria are not met.',
  ),
  'PATHWAY1:FRACTURE_SITE_ELIGIBLE': (
    0,
    'The fracture site is eligible for this pathway.',
    'The fracture site is excluded from this pathway.',
  ),
  'PATHWAY1:RENAL_DYSFUNCTION': (
    0,
    'Kidney function meets the pathway threshold.',
    'Kidney function is below the pathway threshold.',
  ),
  'PATHWAY1:ON_OSTEOPOROSIS_TREATMENT': (
    0,
    'The patient is currently taking osteoporosis treatment.',
    'The patient is not currently taking osteoporosis treatment.',
  ),
  'PATHWAY1:RESIDENTIAL_OR_FRAILTY': (
    1,
    'Residential care, severe frailty or limited life expectancy is confirmed.',
    'No residential care, severe frailty or limited life expectancy is confirmed.',
  ),
  'PATHWAY1:ADHERENCE_CONCERN': (
    -1,
    'There is a concern about treatment adherence.',
    'No treatment-adherence concern is confirmed.',
  ),
  'PATHWAY1:DXA_SCAN_AVAILABILITY': (
    2,
    'A bone-density scan is available or was completed within two years.',
    'A bone-density scan is unavailable or impractical.',
  ),
  'PATHWAY1:T_SCORE_CHECK': (
    -1,
    'The T-score is −2.5 or below at a relevant site.',
    'The T-score threshold of −2.5 or below is not met.',
  ),
  'PATHWAY1:RECENT_MAJOR_FRACTURES': (
    1,
    'A hip, vertebral or multiple-site fracture occurred in the last 24 months.',
    'No hip, vertebral or multiple-site fracture in the last 24 months is confirmed.',
  ),
  'PATHWAY1:HIGH_RISK_CHECK': (
    -1,
    'The very-high-fracture-risk criteria are met.',
    'The very-high-fracture-risk criteria are not met.',
  ),
  'PATHWAY2:ON_ANTIRESORPTIVE_TREATMENT': (
    0,
    'The patient is receiving antiresorptive treatment.',
    'The patient is not receiving antiresorptive treatment.',
  ),
  'PATHWAY2:ANTIRESORPTIVE_TREATMENT_DURATION': (
    0,
    'Treatment duration is more than 12 months.',
    'Treatment duration is not more than 12 months.',
  ),
  'PATHWAY2:TREATMENT_ADHERENCE': (
    0,
    'The patient adhered to the treatment plan.',
    'The patient did not adhere to the treatment plan.',
  ),
  'PATHWAY2:SYMPTOMATIC_FRACTURE': (
    0,
    'A symptomatic fracture occurred in the last 12 months.',
    'No symptomatic fracture in the last 12 months is confirmed.',
  ),
  'PATHWAY2:MULTIPLE_FRACTURES': (
    1,
    'Two or more fractures are confirmed.',
    'Two or more fractures are not confirmed.',
  ),
  'PATHWAY2:CHECK_BMD': (
    0,
    'The T-score is below −3.0 at a site.',
    'The T-score threshold below −3.0 is not met.',
  ),
  'PATHWAY2:MI_OR_STROKE_HISTORY': (
    0,
    'A history of heart attack or stroke is confirmed.',
    'No history of heart attack or stroke is confirmed.',
  ),
  'PATHWAY2:SEQUENCING_WITH_HISTORY': (
    1,
    'The patient is transitioning from denosumab.',
    'The patient is not transitioning from denosumab.',
  ),
  'PATHWAY2:SEQUENCING_NO_HISTORY': (
    1,
    'The patient is transitioning from denosumab.',
    'The patient is not transitioning from denosumab.',
  ),
};

/// Rewrite only established server advice; never calculate a treatment trigger.
String patientAdviceWording(String text) => switch (text) {
  'Ceasing smoking' => 'Stop smoking.',
  'Reducing alcohol intake' => 'Reduce alcohol intake.',
  'Weight bearing exercises' => 'Do regular weight-bearing exercise.',
  'Cholecalciferol 25 microg daily ongoing' =>
    'Take cholecalciferol 25 micrograms once daily. Continue treatment.',
  'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily' =>
    'Take cholecalciferol 75 micrograms once daily for 6 weeks. Then take 25 micrograms once daily.',
  'Calcium supplement 600 mg daily' => 'Take calcium 600 mg once daily.',
  _ => text,
};

List<String> currentPatientAdvice(ClinicalResultsReview review) => [
  for (final advice in review.commonAdvice) patientAdviceWording(advice),
  if (review.vitaminDRecheckBeforeTreatment &&
      !review.commonAdvice.contains(
        'Recheck vitamin D before starting osteoporosis treatment.',
      ))
    'Recheck vitamin D before starting osteoporosis treatment.',
];

String missingRequiredFact(String key) => switch (key) {
  'veryHighFractureRisk' => 'Very-high-fracture-risk status must be confirmed.',
  'osteoporosisTreatmentStatus' => 'Treatment status must be confirmed.',
  'tScoreAtOrBelowMinus2_5AnySite' =>
    'The T-score threshold must be confirmed.',
  'frailtyResidentialOrLimitedLifeExpectancy' =>
    'Residential care, severe frailty or limited life expectancy must be confirmed.',
  'minimalTraumaFracture' => 'The fracture mechanism must be confirmed.',
  'fractureSite' => 'The fracture site must be confirmed.',
  'eGFR' => 'The kidney-function threshold must be confirmed.',
  'antiresorptiveTreatmentStatus' =>
    'Antiresorptive treatment status must be confirmed.',
  'antiresorptiveTreatmentOver12Months' =>
    'Treatment duration must be confirmed.',
  'adheredToTheTreatment' => 'Treatment adherence must be confirmed.',
  'symptomaticFractureInLast12M' =>
    'Recent symptomatic fractures must be confirmed.',
  'multipleFractures' => 'Multiple-fracture status must be confirmed.',
  'lowBMD' => 'The bone-density threshold must be confirmed.',
  'priorMIorStroke' => 'Heart attack or stroke history must be confirmed.',
  'sequencingFromDenosumab' => 'Transition from denosumab must be confirmed.',
  'adherenceConcern' =>
    'More information is required. Confirm treatment-adherence concern.',
  'knownPoorMedicationAdherence' => 'Medication adherence must be confirmed.',
  'cognitiveImpairment' => 'Cognitive impairment must be confirmed.',
  'testAvailability' => 'Bone-density scan availability must be confirmed.',
  'hipVertebralOrMultipleFracturesInLast24M' =>
    'Recent major fractures must be confirmed.',
  'postmenopausal' => 'Postmenopausal status must be confirmed.',
  'sex' => 'Sex recorded at birth is required.',
  'age' => 'Age is required.',
  _ => 'Additional required information must be confirmed.',
};
