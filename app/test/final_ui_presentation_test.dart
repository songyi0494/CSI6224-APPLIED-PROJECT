import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_presentation.dart';
import 'final_ui_evidence_test.dart' show UiEvidenceRepository;

PathwayEvaluation fixture(String key) => PathwayEvaluation.fromJson(
  Map<String, dynamic>.from(
    jsonDecode(
          File('test/fixtures/final_ui_evaluations.json').readAsStringSync(),
        )[key]['evaluation']
        as Map,
  ),
);
ClinicalResultsReview review({
  List<String> lifestyle = const [],
  String? vitamin,
  String? calcium,
  bool recheck = false,
  bool hypo = false,
}) => ClinicalResultsReview.fromJson({
  'vitaminD': {'recommendation': vitamin, 'recheckBeforeTreatment': recheck},
  'calcium': {'recommendation': calcium, 'hypocalcaemia': hypo},
  'lifestyleAdvice': lifestyle,
  'source': {'investigationRevision': 1, 'questionnaireRevision': 1},
});

class ReviewScenario extends UiEvidenceRepository {
  ReviewScenario({
    this.incomplete = false,
    this.saved = false,
    this.stale = false,
    this.hypo = false,
  }) : super('p1');
  final bool incomplete, saved, stale, hypo;
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) async {
    final c = await super.fetchClinicalCase(id);
    return ClinicalCase(
      id: c.id,
      patientId: c.patientId,
      patientName: c.patientName,
      input: c.input,
      status: saved ? ClinicalCaseStatus.approved : c.status,
      revision: c.revision,
      updatedAt: c.updatedAt,
      patientSexAtBirth: c.patientSexAtBirth,
      decisionNotes: saved ? 'Okay' : null,
      clinicianFacts: c.clinicianFacts,
      evaluation: incomplete
          ? const PathwayEvaluation(
              pathway: 'PATHWAY1',
              decision: 'needs_more_information',
              actions: [
                PathwayAction(
                  type: 'medication',
                  description: 'Must not be displayed',
                  raw: {
                    'type': 'medication',
                    'medication': 'Must not be displayed',
                  },
                ),
              ],
              trace: [],
              ruleVersion: 'test',
              routingReason: '',
              missingInputs: ['veryHighFractureRisk'],
            )
          : c.evaluation,
    );
  }

  @override
  Future<ClinicalResultsReview?> getClinicalCaseResultsReview(
    String id,
  ) async => ClinicalResultsReview(
    commonAdvice: const ['Calcium supplement 600 mg daily'],
    investigationRevision: stale ? 0 : 1,
    questionnaireRevision: 1,
    generatedAt: DateTime(2026, 10, 9),
    adviceContractVersion: 'songyi-advice-20261009',
    hypocalcaemiaRevision: 1,
    calciumAuthorityNeedsConfirmation: false,
  );
}

Future<void> mount(
  WidgetTester tester,
  UiEvidenceRepository repo, {
  double width = 1000,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RecommendationReviewScreen(
        caseId: 'evidence-case',
        repository: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final scenario in [
    (smoking: 'Yes', alcohol: 'No', dairy: 2, vitamin: 50.0),
    (smoking: 'No', alcohol: 'Yes', dairy: 5, vitamin: 20.0),
  ]) {
    test(
      'mock advice uses current answers and measurements $scenario',
      () async {
        final repo = MockAppRepository();
        await repo.signIn(
          email: 'patient@example.test',
          password: 'DemoPass123!',
        );
        await repo.submitQuestionnaireResponse(
          answers: {
            'postmenopausal': 'Yes',
            'smoking': scenario.smoking,
            'alcohol': scenario.alcohol,
            'dairyLessThan3Serves': scenario.dairy < 3,
          },
        );
        final c = (await repo.fetchClinicalCases()).single;
        await repo.submitAssessment(
          id: c.id,
          revision: c.revision,
          input: c.input,
        );
        await repo.signIn(
          email: 'clinician@example.test',
          password: 'DemoPass123!',
        );
        await repo.claimClinicalCase(c.id);
        final i = await repo.saveCaseInvestigations(
          caseId: c.id,
          vitaminDLevel: scenario.vitamin,
          ionisedCalcium: 1.2,
          bodyWeightKg: 70,
          expectedRevision: 0,
          authoritativeHypocalcaemia: false,
        );
        final q = (await repo.fetchQuestionnaireResponse(
          patientId: c.patientId,
        ))!;
        final r = await repo.generateClinicalCaseResultsReview(
          caseId: c.id,
          expectedInvestigationRevision: i.revision,
          expectedQuestionnaireRevision: q.revision,
        );
        final advice = currentPatientAdvice(r);
        expect(advice.contains('Stop smoking.'), scenario.smoking == 'Yes');
        expect(
          advice.contains('Reduce alcohol intake.'),
          scenario.alcohol == 'Yes',
        );
        expect(
          advice.contains('Take calcium 600 mg once daily.'),
          scenario.dairy < 3,
        );
        expect(
          advice.contains(
            'Recheck vitamin D before starting osteoporosis treatment.',
          ),
          scenario.vitamin < 25,
        );
      },
    );
  }
  for (final key in ['p1', 'p2']) {
    test(
      '$key explanation contains only saved traversed decisions, at most six lines',
      () {
        final e = fixture(key);
        final lines = recommendationExplanation(e);
        expect(lines.length, inInclusiveRange(3, 6));
        expect(
          lines.every(
            (line) => !line.contains('PATHWAY') && !line.contains('_'),
          ),
          isTrue,
        );
        expect(
          lines,
          contains(
            key == 'p1'
                ? 'The very-high-fracture-risk criteria are met.'
                : 'No history of heart attack or stroke is confirmed.',
          ),
        );
        final unknown = PathwayEvaluation(
          pathway: e.pathway,
          decision: e.decision,
          actions: e.actions,
          trace: const [
            ReasoningTraceEntry(
              ruleId: 'HIGH_RISK_CHECK',
              matched: null,
              reason: 'unknown',
              nodeType: 'decision',
              pathwayId: 'PATHWAY1',
              contractVersion: 'songyi-p1p2-20261009-care',
            ),
          ],
          ruleVersion: e.ruleVersion,
          routingReason: e.routingReason,
        );
        expect(recommendationExplanation(unknown), isEmpty);
      },
    );
    testWidgets(
      '$key default hides technical identities; audit can expand; no irrelevant alcohol advice',
      (tester) async {
        await mount(tester, UiEvidenceRepository(key));
        expect(find.text('Why this recommendation'), findsOneWidget);
        expect(find.textContaining('PATHWAY1'), findsNothing);
        expect(find.textContaining('PATHWAY2'), findsNothing);
        expect(find.text('Stop smoking.'), findsOneWidget);
        expect(find.text('Reduce alcohol intake.'), findsNothing);
        expect(
          find.text(
            'No treatment-specific safety information was supplied for this assessment.',
          ),
          findsNothing,
        );
        await tester.tap(find.text('View technical trace'));
        await tester.pumpAndSettle();
        expect(find.textContaining('PATHWAY1'), findsWidgets);
        expect(find.textContaining('Next node:'), findsNothing);
        expect(find.textContaining('Next:'), findsNothing);
        expect(find.textContaining('Audit ID:'), findsWidgets);
        // Recommendation remains the same exact action bundle from the fixture.
        expect(
          find.textContaining(
            key == 'p1' ? 'privately funded osteoanabolic' : 'Romosozumab',
          ),
          findsWidgets,
        );
      },
    );
  }
  test(
    'A smoking Yes/alcohol No and B smoking No/alcohol Yes retain only supplied advice',
    () {
      expect(currentPatientAdvice(review(lifestyle: ['Ceasing smoking'])), [
        'Stop smoking.',
      ]);
      expect(
        currentPatientAdvice(review(lifestyle: ['Reducing alcohol intake'])),
        ['Reduce alcohol intake.'],
      );
    },
  );
  test(
    'C/D calcium appears only when the backend supplies a recommendation',
    () {
      expect(
        currentPatientAdvice(
          review(calcium: 'Calcium supplement 600 mg daily'),
        ),
        ['Take calcium 600 mg once daily.'],
      );
      expect(currentPatientAdvice(review()), isEmpty);
    },
  );
  test('E maintenance vitamin D wording preserves dose and units', () {
    expect(
      currentPatientAdvice(
        review(vitamin: 'Cholecalciferol 25 microg daily ongoing'),
      ),
      ['Take cholecalciferol 25 micrograms once daily. Continue treatment.'],
    );
  });
  test(
    'F loading course and G explicit recheck use server metadata, not a Flutter threshold',
    () {
      const course =
          'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily';
      expect(currentPatientAdvice(review(vitamin: course)), [
        'Take cholecalciferol 75 micrograms once daily for 6 weeks. Then take 25 micrograms once daily.',
      ]);
      expect(
        currentPatientAdvice(review(vitamin: course, recheck: true)).last,
        'Recheck vitamin D before starting osteoporosis treatment.',
      );
    },
  );
  test(
    'display does not rewrite persisted server advice or interpret numeric labs',
    () {
      final r = ClinicalResultsReview.fromJson({
        'vitaminD': {'level': 20, 'recommendation': null},
        'calcium': {'ionisedCalcium': 1.0, 'recommendation': null},
        'source': {},
      });
      expect(currentPatientAdvice(r), isEmpty);
      expect(r.calciumAuthorityNeedsConfirmation, isFalse);
      final supplied = review(lifestyle: ['Ceasing smoking']);
      currentPatientAdvice(supplied);
      expect(supplied.commonAdvice, ['Ceasing smoking']);
    },
  );
  test('historical trace cannot receive current Boolean clinical wording', () {
    const e = PathwayEvaluation(
      pathway: 'PATHWAY1',
      decision: 'complete',
      actions: [],
      trace: [
        ReasoningTraceEntry(
          ruleId: 'T_SCORE_CHECK',
          matched: true,
          reason: 'historical',
          nodeType: 'decision',
          pathwayId: 'PATHWAY1',
          contractVersion: 'old',
        ),
      ],
      ruleVersion: 'old',
      routingReason: '',
    );
    expect(recommendationExplanation(e), isEmpty);
  });
  testWidgets(
    'missing required fact hides any incomplete action and lists missing item',
    (tester) async {
      await mount(tester, ReviewScenario(incomplete: true));
      expect(
        find.text(
          'More information is required before the recommendation can be completed.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Very-high-fracture-risk status must be confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Must not be displayed'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Approve'), findsNothing);
    },
  );
  testWidgets('saved decision status and clinician note are separate', (
    tester,
  ) async {
    await mount(tester, ReviewScenario(saved: true));
    expect(find.text('Decision status'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Clinician note'), findsOneWidget);
    expect(find.text('Okay'), findsOneWidget);
  });
  testWidgets('stale advice is not presented as current', (tester) async {
    await mount(tester, ReviewScenario(stale: true));
    expect(find.text('Take calcium 600 mg once daily.'), findsNothing);
    expect(find.text('Generate Current Patient Advice'), findsOneWidget);
  });
  testWidgets(
    'current clinician-confirmed advice does not show the retired laboratory-authority warning',
    (tester) async {
      await mount(tester, ReviewScenario(hypo: true));
      expect(
        find.textContaining(
          'Calcium advice needs clinical source confirmation',
        ),
        findsNothing,
      );
      expect(find.text('Take calcium 600 mg once daily.'), findsOneWidget);
    },
  );
  testWidgets(
    'trace remains usable and empty safety is hidden on a 375-pixel screen',
    (tester) async {
      await mount(tester, UiEvidenceRepository('p2'), width: 375);
      expect(find.text('Safety and discussion'), findsNothing);
      await tester.ensureVisible(find.text('View technical trace'));
      await tester.tap(find.text('View technical trace'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No treatment-specific safety information was supplied for this assessment.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
