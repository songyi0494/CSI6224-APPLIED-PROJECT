import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/case_investigations.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_reasons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClinicalCase assessment({
  String pathway = 'PATHWAY1',
  List<ReasoningTraceEntry>? trace,
  Map<String, Object?> facts = const {'eGFR': 54},
  int evaluationRevision = 2,
}) => ClinicalCase(
  id: 'synthetic',
  patientId: 'synthetic-patient',
  patientName: 'Synthetic Patient',
  input: const ClinicalInput(),
  status: ClinicalCaseStatus.evaluated,
  revision: 3,
  updatedAt: DateTime(2026, 10, 11),
  pathwayRevision: 2,
  clinicianFacts: facts,
  evaluation: PathwayEvaluation(
    pathway: pathway,
    decision: 'complete',
    ruleVersion: 'saved-version',
    routingReason: 'saved-routing',
    pathwayRevision: evaluationRevision,
    investigationRevision: 1,
    actions: const [
      PathwayAction(
        type: 'consideration',
        description: 'Original care recommendation',
        raw: {'recommendation': 'Original care recommendation'},
      ),
    ],
    trace:
        trace ??
        const [
          ReasoningTraceEntry(
            ruleId: 'RENAL_DYSFUNCTION',
            matched: true,
            reason: 'saved',
            pathwayId: 'PATHWAY1',
            nodeType: 'decision',
          ),
        ],
  ),
);

class ReadOnlyFixtureRepository extends MockAppRepository {
  ReadOnlyFixtureRepository(this.caseData);
  final ClinicalCase caseData;
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) async => caseData;
  @override
  Future<CaseInvestigations> getCaseInvestigations(String id) async =>
      const CaseInvestigations(
        caseId: 'synthetic',
        vitaminDLevel: 50,
        ionisedCalcium: 1.2,
        bodyWeightKg: 70,
        revision: 1,
        isComplete: true,
      );
  @override
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    String? patientId,
  }) async => null;
  @override
  Future<ClinicalResultsReview?> getClinicalCaseResultsReview(
    String id,
  ) async => null;
}

void main() {
  test(
    'mixed pathway trace retains order while leaves never invent reasons',
    () {
      final data = assessment(
        facts: const {
          'osteoporosisTreatmentStatus': true,
          'antiresorptiveTreatmentStatus': true,
          'adheredToTheTreatment': false,
        },
        trace: const [
          ReasoningTraceEntry(
            ruleId: 'ON_OSTEOPOROSIS_TREATMENT',
            matched: true,
            reason: 'saved',
            pathwayId: 'PATHWAY1',
            nodeType: 'decision',
          ),
          ReasoningTraceEntry(
            ruleId: 'LEAF_REDIRECT_PATHWAY2',
            matched: null,
            reason: 'saved',
            pathwayId: 'PATHWAY1',
            nodeType: 'leaf',
          ),
          ReasoningTraceEntry(
            ruleId: 'ON_ANTIRESORPTIVE_TREATMENT',
            matched: true,
            reason: 'saved',
            pathwayId: 'PATHWAY2',
            nodeType: 'decision',
          ),
          ReasoningTraceEntry(
            ruleId: 'TREATMENT_ADHERENCE',
            matched: false,
            reason: 'saved',
            pathwayId: 'PATHWAY2',
            nodeType: 'decision',
          ),
        ],
      );
      expect(recommendationReasons(data, investigationRevision: 1), [
        'Current osteoporosis treatment is recorded.',
        'Current antiresorptive treatment is recorded.',
        'Non-adherence to the treatment plan is recorded.',
      ]);
      expect(
        recommendationReasons(
          assessment(
            trace: const [
              ReasoningTraceEntry(
                ruleId: 'LEAF_STANDARD_ANTIRESORPTIVE_OPTIONS',
                matched: null,
                reason: 'saved',
                pathwayId: 'PATHWAY2',
                nodeType: 'leaf',
              ),
            ],
          ),
          investigationRevision: 1,
        ),
        [recommendationReasonsUnavailable],
      );
    },
  );
  List<String> reasons(
    String pathway,
    String node,
    bool? matched,
    Map<String, Object?> facts, {
    int revision = 2,
  }) => recommendationReasons(
    assessment(
      pathway: pathway,
      facts: facts,
      evaluationRevision: revision,
      trace: [
        ReasoningTraceEntry(
          ruleId: node,
          matched: matched,
          reason: 'saved',
          pathwayId: pathway,
          nodeType: 'decision',
        ),
      ],
    ),
    investigationRevision: 1,
  );

  test(
    'P1 renal threshold is inclusive at 30 and preserves negative branch',
    () {
      expect(reasons('PATHWAY1', 'RENAL_DYSFUNCTION', true, {'eGFR': 30}), [
        'Recorded eGFR is 30 mL/min (at or above 30 mL/min).',
      ]);
      expect(reasons('PATHWAY1', 'RENAL_DYSFUNCTION', false, {'eGFR': 29}), [
        'Recorded eGFR is 29 mL/min (below 30 mL/min).',
      ]);
      expect(reasons('PATHWAY1', 'RENAL_DYSFUNCTION', true, {'eGFR': 29}), [
        recommendationReasonsUnavailable,
      ]);
    },
  );
  test(
    'P1 BMD boundary is at or below -2.5 without inferring missing sites',
    () {
      expect(
        reasons('PATHWAY1', 'T_SCORE_CHECK', true, {'hipTscore': -2.5}).single,
        contains('At least one is at or below -2.5'),
      );
      expect(reasons('PATHWAY1', 'T_SCORE_CHECK', false, {'hipTscore': -2.4}), [
        recommendationReasonsUnavailable,
      ]);
      expect(
        reasons('PATHWAY1', 'T_SCORE_CHECK', false, {
          'hipTscore': -2.4,
          'femoralNeckTscore': -1,
          'lumbarSpineTscore': -2,
        }).single,
        contains('All three are above -2.5'),
      );
    },
  );
  test('P1 composite negatives need every recorded value', () {
    expect(
      reasons('PATHWAY1', 'ADHERENCE_CONCERN', false, {
        'knownPoorMedicationAdherence': false,
      }),
      [recommendationReasonsUnavailable],
    );
    expect(
      reasons('PATHWAY1', 'ADHERENCE_CONCERN', false, {
        'knownPoorMedicationAdherence': false,
        'cognitiveImpairment': false,
      }).single,
      contains('Neither poor'),
    );
    expect(
      reasons('PATHWAY1', 'ADHERENCE_CONCERN', true, {
        'knownPoorMedicationAdherence': true,
        'cognitiveImpairment': false,
      }).single,
      startsWith('Poor medication adherence is recorded'),
    );
    expect(
      reasons('PATHWAY1', 'RESIDENTIAL_OR_FRAILTY', true, {
        'liveInResidentialCare': false,
        'clinicalFrailtyScore': 6,
        'lifeExpectancy': 7,
      }).single,
      contains('was met'),
    );
    expect(
      reasons('PATHWAY1', 'RESIDENTIAL_OR_FRAILTY', false, {
        'liveInResidentialCare': false,
        'clinicalFrailtyScore': 5,
        'lifeExpectancy': 7,
      }).single,
      contains('was not met'),
    );
  });
  test(
    'P1 very high risk preserves AND structure and inclusive FRAX boundaries',
    () {
      final facts = <String, Object?>{
        'femoralNeckTscore': -3.0,
        'hipTscore': -2,
        'lumbarSpineTscore': -2,
        'recentFractureWithin2Y': false,
        'historyOf2orMoreFractures': false,
        'clinicalRiskFactors': false,
        'FRAX10YmajorOsteoporoticFractureRiskPercent': 30,
        'FRAX10YmajorHipFractureRiskPercent': 1,
      };
      expect(
        reasons('PATHWAY1', 'HIGH_RISK_CHECK', true, facts).single,
        contains('was met'),
      );
      facts['FRAX10YmajorOsteoporoticFractureRiskPercent'] = 29;
      facts['FRAX10YmajorHipFractureRiskPercent'] = 4.5;
      expect(
        reasons('PATHWAY1', 'HIGH_RISK_CHECK', true, facts).single,
        contains('hip fracture risk at least 4.5%'),
      );
      facts['femoralNeckTscore'] = -2.9;
      expect(
        reasons('PATHWAY1', 'HIGH_RISK_CHECK', false, facts).single,
        contains('was not met'),
      );
      expect(reasons('PATHWAY1', 'HIGH_RISK_CHECK', true, facts), [
        recommendationReasonsUnavailable,
      ]);
    },
  );
  final p2 = <(String, String, String, String)>[
    (
      'ON_ANTIRESORPTIVE_TREATMENT',
      'antiresorptiveTreatmentStatus',
      'Current antiresorptive treatment is recorded.',
      'No current antiresorptive treatment is recorded.',
    ),
    (
      'TREATMENT_ADHERENCE',
      'adheredToTheTreatment',
      'Adherence to the treatment plan is recorded.',
      'Non-adherence to the treatment plan is recorded.',
    ),
    (
      'SYMPTOMATIC_FRACTURE',
      'symptomaticFractureInLast12M',
      'A symptomatic fracture in the last 12 months is recorded.',
      'No symptomatic fracture in the last 12 months is recorded.',
    ),
    (
      'MULTIPLE_FRACTURES',
      'multipleFractures',
      'Two or more fractures are recorded.',
      'Two or more fractures are not recorded.',
    ),
    (
      'CHECK_BMD',
      'lowBMD',
      'A BMD T-score below -3.0 at at least one site is recorded.',
      'A BMD T-score below -3.0 at any site is not recorded.',
    ),
    (
      'MI_OR_STROKE_HISTORY',
      'priorMIorStroke',
      'A history of myocardial infarction or stroke is recorded.',
      'No history of myocardial infarction or stroke is recorded.',
    ),
    (
      'SEQUENCING_WITH_HISTORY',
      'sequencingFromDenosumab',
      'Transition from denosumab is recorded.',
      'Transition from denosumab is not recorded.',
    ),
    (
      'SEQUENCING_NO_HISTORY',
      'sequencingFromDenosumab',
      'Transition from denosumab is recorded.',
      'Transition from denosumab is not recorded.',
    ),
  ];
  for (final (node, fact, yes, no) in p2) {
    test('P2 $node preserves positive and negative findings', () {
      expect(reasons('PATHWAY2', node, true, {fact: true}), [yes]);
      expect(reasons('PATHWAY2', node, false, {fact: false}), [no]);
      expect(reasons('PATHWAY2', node, true, {fact: false}), [
        recommendationReasonsUnavailable,
      ]);
    });
  }
  test('duration boolean does not invent a disputed numerical threshold', () {
    final reason = reasons(
      'PATHWAY2',
      'ANTIRESORPTIVE_TREATMENT_DURATION',
      true,
      {'antiresorptiveTreatmentDuration': true},
    ).single;
    expect(reason, contains('criterion was met'));
    expect(reason, isNot(contains('12')));
    expect(
      reasons('PATHWAY2', 'ANTIRESORPTIVE_TREATMENT_DURATION', false, {
        'antiresorptiveTreatmentDuration': false,
      }).single,
      contains('was not met'),
    );
  });
  test(
    'unknown, absent, invalid and stale facts never become negative findings',
    () {
      for (final value in [null, 'No', double.nan]) {
        expect(
          reasons('PATHWAY1', 'RENAL_DYSFUNCTION', false, {'eGFR': value}),
          [recommendationReasonsUnavailable],
        );
      }
      expect(reasons('PATHWAY1', 'RENAL_DYSFUNCTION', null, {'eGFR': 54}), [
        recommendationReasonsUnavailable,
      ]);
      expect(
        reasons('PATHWAY1', 'RENAL_DYSFUNCTION', true, {
          'eGFR': 54,
        }, revision: 1),
        [recommendationReasonsUnavailable],
      );
      expect(recommendationReasons(assessment(), investigationRevision: 2), [
        recommendationReasonsUnavailable,
      ]);
      expect(reasons('PATHWAY3', 'RENAL_DYSFUNCTION', true, {'eGFR': 54}), [
        recommendationReasonsUnavailable,
      ]);
      expect(reasons('PATHWAY1', 'UNSUPPORTED_NODE', false, {}), [
        recommendationReasonsUnavailable,
      ]);
    },
  );
  test(
    'legacy snapshots retain inverse match semantics and do not use current facts',
    () {
      final caseData = assessment(
        facts: {'eGFR': 5},
        trace: const [
          ReasoningTraceEntry(
            ruleId: 'RENAL_DYSFUNCTION',
            matched: false,
            reason: 'saved',
            input: {'eGFR': 54},
          ),
          ReasoningTraceEntry(
            ruleId: 'T_SCORE',
            matched: false,
            reason: 'saved',
            input: {'T-score': -2.5},
          ),
        ],
      );
      final result = recommendationReasons(caseData, investigationRevision: 1);
      expect(result.first, contains('54 mL/min (at or above 30'));
      expect(result.last, contains('At least one is at or below -2.5'));
      expect(caseData.clinicianFacts['eGFR'], 5);
      expect(caseData.evaluation!.trace.first.matched, false);
      expect(
        caseData.evaluation!.actions.single.description,
        'Original care recommendation',
      );
    },
  );
  for (final size in [const Size(1440, 900), const Size(360, 800)]) {
    testWidgets('P2 explanation and expanded original trace wrap at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final caseData = assessment(
        pathway: 'PATHWAY2',
        facts: {'lowBMD': true, 'priorMIorStroke': false},
        trace: const [
          ReasoningTraceEntry(
            ruleId: 'CHECK_BMD',
            matched: true,
            reason: 'saved',
            pathwayId: 'PATHWAY2',
            nodeType: 'decision',
          ),
          ReasoningTraceEntry(
            ruleId: 'MI_OR_STROKE_HISTORY',
            matched: false,
            reason: 'saved',
            pathwayId: 'PATHWAY2',
            nodeType: 'decision',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationReviewScreen(
            caseId: 'synthetic',
            repository: ReadOnlyFixtureRepository(caseData),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('below -3.0'), findsOneWidget);
      expect(find.textContaining('No history of myocardial'), findsOneWidget);
      final tile = find.text('View detailed decision trace');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Does the patient have a BMD T-score below -3.0 at any site?',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Does the patient have a history of myocardial infarction(MI) or stroke?',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'adds grounded reasons without changing care or decision controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationReviewScreen(
            caseId: 'synthetic',
            repository: ReadOnlyFixtureRepository(assessment()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Why this recommendation'), findsOneWidget);
      expect(find.textContaining('54 mL/min'), findsOneWidget);
      expect(find.text('Original care recommendation'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Withhold'), findsOneWidget);
      expect(find.text('Save decision'), findsOneWidget);
      final expansion = find.text('View detailed decision trace');
      await tester.ensureVisible(expansion);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(
        find.text("What is the patient's eGFR value? (Unit: mL/min)"),
        findsOneWidget,
      );
      expect(find.text('Rule checked'), findsOneWidget);
    },
  );
}
