import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/models/case_investigations.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/models/patient_questionnaire_catalog.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/screens/questionnaire_response_screen.dart';
import 'package:csi6224_patient_feedback/screens/investigations_screen.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_presentation.dart';

Future<({MockAppRepository repo, String id, String patient})> prepare({
  bool dairy = false,
  double? vitamin = 50,
  bool? hypo = false,
  bool save = true,
}) async {
  final repo = MockAppRepository();
  await repo.signIn(email: 'patient@example.test', password: 'DemoPass123!');
  await repo.submitQuestionnaireResponse(
    answers: {
      'postmenopausal': 'Yes',
      'smoking': 'No',
      'alcohol': 'No',
      'dairyLessThan3Serves': dairy,
    },
  );
  final c = (await repo.fetchClinicalCases()).single;
  await repo.submitAssessment(id: c.id, revision: c.revision, input: c.input);
  await repo.signIn(email: 'clinician@example.test', password: 'DemoPass123!');
  await repo.claimClinicalCase(c.id);
  if (save) {
    await repo.saveCaseInvestigations(
      caseId: c.id,
      vitaminDLevel: vitamin,
      ionisedCalcium: 1.08,
      bodyWeightKg: 70,
      authoritativeHypocalcaemia: hypo,
      expectedRevision: 0,
    );
  }
  return (repo: repo, id: c.id, patient: c.patientId);
}

Future<List<String>> advice(
  ({MockAppRepository repo, String id, String patient}) c,
) async {
  final i = await c.repo.getCaseInvestigations(c.id);
  final q = (await c.repo.fetchQuestionnaireResponse(patientId: c.patient))!;
  return currentPatientAdvice(
    await c.repo.generateClinicalCaseResultsReview(
      caseId: c.id,
      expectedInvestigationRevision: i.revision,
      expectedQuestionnaireRevision: q.revision,
    ),
  );
}

class CaptureRepository extends MockAppRepository {
  Map<String, Object?>? submitted;
  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) async {
    submitted = answers;
    return super.submitQuestionnaireResponse(answers: answers);
  }
}

void main() {
  test(
    'approval RPC includes the confirmation revision that was reviewed',
    () async {
      Map<String, dynamic>? sent;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204, request: request);
        }),
      );
      addTearDown(client.dispose);
      final c = ClinicalCase(
        id: 'case-id',
        patientId: 'patient-id',
        patientName: 'Synthetic',
        input: const ClinicalInput(),
        status: ClinicalCaseStatus.evaluated,
        revision: 1,
        updatedAt: DateTime(2026, 10, 9),
        evaluation: const PathwayEvaluation(
          pathway: 'PATHWAY1',
          decision: 'complete',
          actions: [],
          trace: [],
          ruleVersion: 'songyi-p1p2-20261009-care',
          routingReason: '',
          pathwayRevision: 3,
          investigationRevision: 4,
        ),
      );
      final r = ClinicalResultsReview(
        commonAdvice: const [],
        investigationRevision: 4,
        questionnaireRevision: 5,
        hypocalcaemiaRevision: 6,
        adviceContractVersion: 'songyi-advice-20261009',
        generatedAt: DateTime(2026, 10, 9),
      );
      await SupabaseAppRepository(client).recordClinicianDecision(
        assessment: c,
        decision: ClinicalCaseStatus.approved,
        notes: 'Reviewed',
        resultsReview: r,
      );
      expect(sent!['p_expected_hypocalcaemia_revision'], 6);
      expect(sent!['p_expected_investigation_revision'], 4);
      expect(sent!['p_expected_questionnaire_revision'], 5);
    },
  );
  for (final dairy in [true, false]) {
    for (final hypo in [true, false]) {
      test(
        'calcium OR uses Boolean dairy=$dairy and confirmed hypocalcaemia=$hypo once',
        () async {
          final c = await prepare(dairy: dairy, hypo: hypo);
          final result = await advice(c);
          expect(
            result
                .where((line) => line == 'Take calcium 600 mg once daily.')
                .length,
            dairy || hypo ? 1 : 0,
          );
        },
      );
    }
  }
  for (final vitamin in <double?>[null, 50, 30, 20, 80]) {
    test('vitamin D $vitamin uses one current baseline result', () async {
      final c = await prepare(vitamin: vitamin);
      final result = await advice(c);
      expect(
        result.any((text) => text.contains('cholecalciferol')),
        vitamin != null && vitamin <= 75,
      );
      expect(
        result.contains(
          'Recheck vitamin D before starting osteoporosis treatment.',
        ),
        vitamin != null && vitamin < 25,
      );
      if (vitamin == 50) {
        expect(
          result,
          contains(
            'Take cholecalciferol 25 micrograms once daily. Continue treatment.',
          ),
        );
      }
      if (vitamin == 30 || vitamin == 20) {
        expect(
          result,
          contains(
            'Take cholecalciferol 75 micrograms once daily for 6 weeks. Then take 25 micrograms once daily.',
          ),
        );
      }
    });
  }
  for (final path in ['P1', 'P2']) {
    test(
      '$path mock clinician approval retains the recheck in patient projection',
      () async {
        final c = await prepare(vitamin: 20);
        final facts = <String, Object>{
          'minimalTraumaFracture': 'yes',
          'fractureSite': 'hip',
          'eGFR': true,
          'osteoporosisTreatmentStatus': path == 'P2',
        };
        if (path == 'P1') {
          facts['frailtyResidentialOrLimitedLifeExpectancy'] = true;
        } else {
          facts['antiresorptiveTreatmentStatus'] = true;
          facts['antiresorptiveTreatmentOver12Months'] = false;
        }
        for (final entry in facts.entries) {
          await c.repo.savePathwayAnswer(
            caseId: c.id,
            fieldKey: entry.key,
            value: entry.value,
          );
        }
        expect(
          await c.repo.evaluatePathway(caseId: c.id),
          isA<CompletedPathwayEvaluation>(),
        );
        final inv = await c.repo.getCaseInvestigations(c.id);
        final q = (await c.repo.fetchQuestionnaireResponse(
          patientId: c.patient,
        ))!;
        final r = await c.repo.generateClinicalCaseResultsReview(
          caseId: c.id,
          expectedInvestigationRevision: inv.revision,
          expectedQuestionnaireRevision: q.revision,
        );
        final assessment = await c.repo.fetchClinicalCase(c.id);
        await c.repo.recordClinicianDecision(
          assessment: assessment,
          decision: ClinicalCaseStatus.approved,
          notes: 'Reviewed',
          resultsReview: r,
        );
        await c.repo.signIn(
          email: 'patient@example.test',
          password: 'DemoPass123!',
        );
        final result = (await c.repo.fetchPatientApprovedResults()).single;
        expect(
          result.lifestyleRecommendations
              .where(
                (text) =>
                    text ==
                    'Recheck vitamin D before starting osteoporosis treatment.',
              )
              .length,
          1,
        );
      },
    );
  }
  test(
    'missing confirmation fails closed; advice-only confirmation preserves baseline revision',
    () async {
      final c = await prepare(hypo: null);
      await expectLater(advice(c), throwsA(isA<AppException>()));
      final before = await c.repo.getCaseInvestigations(c.id);
      final confirmed = await c.repo.confirmCaseHypocalcaemia(
        caseId: c.id,
        value: false,
        expectedRevision: 0,
      );
      expect(confirmed.revision, before.revision);
      expect(confirmed.hypocalcaemiaRevision, 1);
      expect(confirmed.authoritativeHypocalcaemia, false);
      expect(
        await advice(c),
        isNot(contains('Take calcium 600 mg once daily.')),
      );
    },
  );
  test(
    'active patient contract excludes the retired numeric dairy writer and all falls inputs',
    () {
      expect(patientQuestionnaireVisibleKeys, contains('dairyLessThan3Serves'));
      expect(
        productionQuestionnaireAnswerKeys,
        isNot(contains('dietaryDairyServings')),
      );
      for (final key in [
        'fallsPast12Months',
        'fearOfFalling',
        'movementRehabilitationInterest',
      ]) {
        expect(patientQuestionnaireVisibleKeys, isNot(contains(key)));
      }
      expect(
        () => SupabaseAppRepository.governedQuestionnaireAnswers({
          'dietaryDairyServings': 2,
        }),
        throwsA(isA<AppException>()),
      );
      for (final value in [null, 2, 'Yes']) {
        expect(
          () => SupabaseAppRepository.governedQuestionnaireAnswers({
            'dairyLessThan3Serves': value,
          }),
          throwsA(isA<AppException>()),
        );
      }
      expect(
        SupabaseAppRepository.governedQuestionnaireAnswers({
          'dairyLessThan3Serves': false,
        })['dairyLessThan3Serves'],
        false,
      );
    },
  );
  testWidgets(
    'numeric dairy history cannot prefill Boolean No or bypass the question',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = CaptureRepository();
      await repo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionnaireResponseScreen(
            repository: repo,
            form: await repo.fetchQuestionnaireForm(),
            profileSexAtBirth: 'female',
            initialAnswers: const {
              'postmenopausal': 'Yes',
              'smoking': 'No',
              'alcohol': 'No',
              'dietaryDairyServings': 5,
            },
          ),
        ),
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.text(
          'Do you usually have fewer than 3 serves of dairy foods per day?',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 serve is about 250 mL milk, 200 g yoghurt, or 40 g cheese.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<bool>>(
              find.byType(DropdownButtonFormField<bool>),
            )
            .initialValue,
        isNull,
      );
      final button = find.widgetWithText(FilledButton, 'Review your answers');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(repo.submitted, isNull);
      final field = find.byType(DropdownButtonFormField<bool>);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('No').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Submit questionnaire'),
      );
      await tester.pumpAndSettle();
      expect(repo.submitted!['dairyLessThan3Serves'], false);
      expect(repo.submitted!.containsKey('dietaryDairyServings'), false);
    },
  );
  testWidgets(
    'blank investigations can be explicitly saved without becoming normal or deficient',
    (tester) async {
      final c = await prepare(save: false);
      await tester.pumpWidget(
        MaterialApp(
          home: InvestigationsScreen(
            repository: c.repo,
            investigations: CaseInvestigations.empty(c.id),
          ),
        ),
      );
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final inv = await c.repo.getCaseInvestigations(c.id);
      expect(inv.vitaminDLevel, isNull);
      expect(inv.ionisedCalcium, isNull);
      expect(inv.bodyWeightKg, isNull);
      expect(inv.authoritativeHypocalcaemia, isNull);
      expect(inv.canStartPathway, true);
    },
  );
  test(
    'clinician confirmation RPC transports Boolean value and dedicated expected revision',
    () async {
      Map<String, dynamic>? body;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, endsWith('/confirm_case_hypocalcaemia'));
          return http.Response(
            jsonEncode({
              'caseId': 'case-id',
              'vitaminD': {'value': null, 'unit': 'nmol/L'},
              'ionisedCalcium': {'value': 1.08, 'unit': 'mmol/L'},
              'bodyWeight': {'value': null, 'unit': 'kg'},
              'revision': 4,
              'completed': true,
              'authoritativeHypocalcaemia': false,
              'hypocalcaemiaRevision': 2,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final inv = await SupabaseAppRepository(client).confirmCaseHypocalcaemia(
        caseId: 'case-id',
        value: false,
        expectedRevision: 1,
      );
      expect(body, {
        'p_case_id': 'case-id',
        'p_value': false,
        'p_expected_revision': 1,
      });
      expect(inv.authoritativeHypocalcaemia, false);
      expect(inv.hypocalcaemiaRevision, 2);
      expect(inv.revision, 4);
    },
  );
}
