import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'live_pathway_contract_test.dart' show clinicianCase;

Future<void> choose(WidgetTester tester, String option) async {
  final control = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
  final next = find.widgetWithText(FilledButton, 'Next');
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'compatibility input models share Boolean eGFR and do not derive old numeric answers',
    () {
      expect(ClinicalInput.fromFacts({'eGFR': true}).egfr, true);
      expect(Pathway1ClinicianInput.fromJson({'eGFR': false}).egfr, false);
      expect(ClinicalInput.fromFacts({'eGFR': 60}).egfr, isNull);
      expect(Pathway1ClinicianInput.fromJson({'eGFR': 60}).egfr, isNull);
      expect(const ClinicalInput(egfr: true).toFacts()['eGFR'], true);
      expect(
        const Pathway1ClinicianInput(egfr: false).toEvaluatorFacts()['eGFR'],
        false,
      );
    },
  );
  test('saved contract version controls threshold trace meaning', () {
    final evaluation = PathwayEvaluation.fromJson({
      'status': 'complete',
      'pathwayId': 'PATHWAY1',
      'contractVersion': 'songyi-p1p2-20261008',
      'actions': [],
      'trace': [
        {
          'nodeId': 'RENAL_DYSFUNCTION',
          'nodeType': 'decision',
          'pathwayId': 'PATHWAY1',
          'matched': true,
        },
      ],
    });
    expect(
      clinicalTracePresentation(evaluation.trace.single).details.single,
      contains('≥30 mL/min = Yes'),
    );
    final oldDuration = ReasoningTraceEntry.fromJson({
      'nodeId': 'ANTIRESORPTIVE_TREATMENT_DURATION',
      'nodeType': 'decision',
      'pathwayId': 'PATHWAY2',
      'matched': true,
    });
    expect(
      clinicalTracePresentation(oldDuration).title,
      'Historical treatment duration decision',
    );
    expect(
      clinicalTracePresentation(oldDuration).details.single,
      contains('Historical duration answer'),
    );
  });
  test(
    'active repository rejects numeric eGFR and retired duration key',
    () async {
      final setup = await clinicianCase();
      for (final value in [29, 30, 60, 'true']) {
        await expectLater(
          setup.repository.savePathwayAnswer(
            caseId: setup.caseId,
            fieldKey: 'eGFR',
            value: value,
          ),
          throwsA(isA<AppException>()),
        );
      }
      await expectLater(
        setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'antiresorptiveTreatmentDuration',
          value: true,
        ),
        throwsA(isA<AppException>()),
      );
      await setup.repository.savePathwayAnswer(
        caseId: setup.caseId,
        fieldKey: 'eGFR',
        value: true,
      );
      final assessment = await setup.repository.fetchClinicalCase(setup.caseId);
      expect(assessment.clinicianFacts['eGFR'], true);
      expect(assessment.clinicianInput?.egfr, isTrue);
    },
  );

  test(
    'missing structured fracture answer is requested despite patient free text',
    () async {
      final setup = await clinicianCase(confirmEligibility: false);
      final result =
          await setup.repository.evaluatePathway(caseId: setup.caseId)
              as PathwayQuestionStep;
      expect(result.requiredFacts, ['minimalTraumaFracture']);
      expect(result.trace.first.nodeId, 'P1_DEMOGRAPHIC_ELIGIBILITY');
    },
  );

  for (final value in ['no', 'not_sure']) {
    test(
      'fracture $value never completes or becomes inferred eligibility',
      () async {
        final setup = await clinicianCase(confirmEligibility: false);
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'minimalTraumaFracture',
          value: value,
        );
        final result = await setup.repository.evaluatePathway(
          caseId: setup.caseId,
        );
        expect(result, isA<PathwayRuntimeError>());
        expect(
          (await setup.repository.fetchClinicalCase(setup.caseId)).status,
          ClinicalCaseStatus.inProgress,
        );
        expect(
          (await setup.repository.fetchClinicalCase(
            setup.caseId,
          )).clinicianFacts['minimalTraumaFracture'],
          value,
        );
      },
    );
  }

  for (final site in ['hand', 'foot', 'face', 'ankle']) {
    test('excluded $site is recorded separately and requires review', () async {
      final setup = await clinicianCase();
      await setup.repository.savePathwayAnswer(
        caseId: setup.caseId,
        fieldKey: 'fractureSite',
        value: site,
      );
      expect(
        await setup.repository.evaluatePathway(caseId: setup.caseId),
        isA<PathwayRuntimeError>(),
      );
      expect(
        (await setup.repository.fetchClinicalCase(setup.caseId)).status,
        ClinicalCaseStatus.inProgress,
      );
    });
  }

  for (final answer in [false, true]) {
    test(
      'P2 strict-duration $answer selects the corresponding branch',
      () async {
        final setup = await clinicianCase();
        for (final entry in {
          'eGFR': true,
          'osteoporosisTreatmentStatus': true,
          'antiresorptiveTreatmentStatus': true,
          'antiresorptiveTreatmentOver12Months': answer,
        }.entries) {
          await setup.repository.savePathwayAnswer(
            caseId: setup.caseId,
            fieldKey: entry.key,
            value: entry.value,
          );
        }
        final result = await setup.repository.evaluatePathway(
          caseId: setup.caseId,
        );
        if (answer) {
          expect(result, isA<PathwayQuestionStep>());
          expect((result as PathwayQuestionStep).requiredFacts, [
            'adheredToTheTreatment',
          ]);
        } else {
          expect(result, isA<CompletedPathwayEvaluation>());
          expect(
            (result as CompletedPathwayEvaluation)
                .actions
                .single['recommendation'],
            contains('standard antiresorptive'),
          );
        }
      },
    );
  }

  test('review errors retain readable messages', () {
    final result =
        LivePathwayResult.fromJson({
              'status': 'error',
              'pathwayId': 'PATHWAY1',
              'error': {
                'code': 'ELIGIBILITY_INFORMATION_REQUIRED',
                'message': 'Confirm the fracture site.',
              },
              'trace': [],
            })
            as PathwayRuntimeError;
    expect(result.message, 'Confirm the fracture site.');
  });

  testWidgets(
    'structured eligibility precedes Boolean eGFR with no numeric control',
    (tester) async {
      final setup = await clinicianCase(confirmEligibility: false);
      await tester.pumpWidget(
        MaterialApp(
          home: PathwayQuestionScreen(
            caseId: setup.caseId,
            repository: setup.repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await choose(tester, 'Yes');
      final site = find.byType(DropdownButtonFormField<String>);
      await tester.tap(site);
      await tester.pumpAndSettle();
      for (final label in ['Hand', 'Foot', 'Face', 'Ankle']) {
        expect(find.text(label), findsNothing);
      }
      expect(
        find.text('Excluded site — hand, foot, face, or ankle'),
        findsOneWidget,
      );
      expect(find.text('Wrist / forearm'), findsOneWidget);
      expect(find.text('Leg, ankle or foot'), findsNothing);
      await tester.tap(find.text('Hip').last);
      await tester.pumpAndSettle();
      final next = find.widgetWithText(FilledButton, 'Next');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Select an answer'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets(
    'Not sure stays recorded and displays information-required message',
    (tester) async {
      final setup = await clinicianCase(confirmEligibility: false);
      await tester.pumpWidget(
        MaterialApp(
          home: PathwayQuestionScreen(
            caseId: setup.caseId,
            repository: setup.repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'Not sure');
      expect(
        find.textContaining(
          'More information is required before the recommendation can be completed.',
        ),
        findsOneWidget,
      );
      final assessment = await setup.repository.fetchClinicalCase(setup.caseId);
      expect(assessment.status, ClinicalCaseStatus.inProgress);
      expect(assessment.clinicianFacts['minimalTraumaFracture'], 'not_sure');
    },
  );
}
