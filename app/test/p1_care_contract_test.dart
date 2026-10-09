import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'live_pathway_contract_test.dart' show clinicianCase;

const careKey = 'frailtyResidentialOrLimitedLifeExpectancy';
const careHelper =
    'Lives in residential care, Clinical Frailty Scale score 6 or higher, or life expectancy less than 7 years.';
Future<({MockAppRepository repository, String caseId})> atCare() async {
  final setup = await clinicianCase();
  await setup.repository.savePathwayAnswer(
    caseId: setup.caseId,
    fieldKey: 'eGFR',
    value: true,
  );
  await setup.repository.savePathwayAnswer(
    caseId: setup.caseId,
    fieldKey: 'osteoporosisTreatmentStatus',
    value: false,
  );
  return setup;
}

void main() {
  for (final reason in [
    'A residential care',
    'B Clinical Frailty Scale 6 or higher',
    'C life expectancy less than 7 years',
  ]) {
    test(
      '$reason: one clinician Yes selects the existing denosumab branch',
      () async {
        final setup = await atCare();
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: careKey,
          value: true,
        );
        final result =
            await setup.repository.evaluatePathway(caseId: setup.caseId)
                as CompletedPathwayEvaluation;
        expect(
          result.trace
              .lastWhere((t) => t.nodeId == 'RESIDENTIAL_OR_FRAILTY')
              .matched,
          true,
        );
        expect(result.actions, [
          {
            'type': 'medication',
            'medication': 'Denosumab',
            'dose': '60mg',
            'route': 'subcut',
            'frequency': '6 monthly',
          },
          {'type': 'followUp', 'destination': 'GP'},
        ]);
        final facts = (await setup.repository.fetchClinicalCase(
          setup.caseId,
        )).clinicianFacts;
        for (final old in [
          'liveInResidentialCare',
          'clinicalFrailtyScore',
          'lifeExpectancy',
        ]) {
          expect(facts.containsKey(old), false);
        }
      },
    );
  }
  test('D confirmed No continues to the existing adherence decision', () async {
    final setup = await atCare();
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: careKey,
      value: false,
    );
    final result =
        await setup.repository.evaluatePathway(caseId: setup.caseId)
            as PathwayQuestionStep;
    expect(result.nodeId, 'ADHERENCE_CONCERN');
    expect(result.requiredFacts, ['adherenceConcern']);
  });
  test(
    'E missing confirmation requests one Boolean with the full OR helper',
    () async {
      final setup = await atCare();
      final result =
          await setup.repository.evaluatePathway(caseId: setup.caseId)
              as PathwayQuestionStep;
      expect(result.requiredFacts, [careKey]);
      expect(result.helperText, careHelper);
      expect(result.question, 'Does the patient have any of these factors?');
    },
  );
  test(
    'registry retires all three components and has no numeric clinician pathway inputs',
    () {
      expect(pathwayFactRegistry[careKey]!.kind, PathwayFactKind.boolean);
      expect(pathwayFactRegistry[careKey]!.helperText, careHelper);
      for (final old in [
        'liveInResidentialCare',
        'clinicalFrailtyScore',
        'lifeExpectancy',
      ]) {
        expect(pathwayFactRegistry.containsKey(old), false);
      }
      expect(
        pathwayFactRegistry.values.any(
          (fact) => fact.kind == PathwayFactKind.number,
        ),
        false,
      );
    },
  );
  test(
    'models keep historical values readable without emitting or deriving current care authority',
    () {
      final old = ClinicalInput.fromFacts({
        'liveInResidentialCare': true,
        'clinicalFrailtyScore': 7,
        'lifeExpectancy': 5,
      });
      expect(old.frailty, 7);
      expect(old.lifeExpectancy, 5);
      expect(old.residentialCare, true);
      expect(old.frailtyResidentialOrLimitedLifeExpectancy, isNull);
      for (final key in [
        'liveInResidentialCare',
        'clinicalFrailtyScore',
        'lifeExpectancy',
      ]) {
        expect(old.toFacts().containsKey(key), false);
      }
      final batch = Pathway1ClinicianInput.fromJson({
        'clinicalFrailtyScore': 7,
        'lifeExpectancy': 5,
      });
      expect(batch.frailtyResidentialOrLimitedLifeExpectancy, isNull);
      expect(
        batch.toEvaluatorFacts().containsKey('clinicalFrailtyScore'),
        false,
      );
      expect(batch.toEvaluatorFacts().containsKey('lifeExpectancy'), false);
      final unknown = ClinicalInput.fromFacts({
        'clinicalFrailtyScore': true,
        'lifeExpectancy': 'Unavailable',
        'liveInResidentialCare': 'Not sure',
      });
      expect(unknown.frailtyResidentialOrLimitedLifeExpectancy, isNull);
      expect(
        const Pathway1ClinicianInput(
          frailtyResidentialOrLimitedLifeExpectancy: false,
        ).toEvaluatorFacts()[careKey],
        false,
      );
    },
  );
  test(
    'numeric, string, uncertain and retired component answers are rejected',
    () async {
      final setup = await atCare();
      for (final value in [6, 7, 5, 'true', 'No', 'not_sure']) {
        await expectLater(
          setup.repository.savePathwayAnswer(
            caseId: setup.caseId,
            fieldKey: careKey,
            value: value,
          ),
          throwsA(isA<AppException>()),
        );
      }
      for (final key in [
        'liveInResidentialCare',
        'clinicalFrailtyScore',
        'lifeExpectancy',
      ]) {
        await expectLater(
          setup.repository.savePathwayAnswer(
            caseId: setup.caseId,
            fieldKey: key,
            value: true,
          ),
          throwsA(isA<AppException>()),
        );
      }
    },
  );
  test(
    'trace labels distinguish current OR confirmation from older care-component snapshots',
    () {
      final current = ReasoningTraceEntry.fromJson({
        'pathwayId': 'PATHWAY1',
        'nodeId': 'RESIDENTIAL_OR_FRAILTY',
        'nodeType': 'decision',
        'matched': true,
        'contractVersion': 'songyi-p1p2-20261009-care',
      });
      expect(
        clinicalTracePresentation(current).title,
        'Residential care, severe frailty, or limited life expectancy',
      );
      expect(
        clinicalTracePresentation(current).details.single,
        contains('= Yes'),
      );
      final old = ReasoningTraceEntry.fromJson({
        'pathwayId': 'PATHWAY1',
        'nodeId': 'RESIDENTIAL_OR_FRAILTY',
        'nodeType': 'decision',
        'matched': true,
        'contractVersion': 'songyi-p1p2-20261009-bmd',
      });
      expect(
        clinicalTracePresentation(old).details.single,
        contains('Historical care-component decision'),
      );
    },
  );
  testWidgets('care control is one Yes/No question; blank is not saved as No', (
    tester,
  ) async {
    final setup = await atCare();
    await tester.pumpWidget(
      MaterialApp(
        home: PathwayQuestionScreen(
          caseId: setup.caseId,
          repository: setup.repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Does the patient have any of these factors?'),
      findsWidgets,
    );
    expect(find.text(careHelper), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    final next = find.widgetWithText(FilledButton, 'Next');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Clinician confirmation is required'), findsOneWidget);
    expect(
      (await setup.repository.fetchClinicalCase(
        setup.caseId,
      )).clinicianFacts.containsKey(careKey),
      false,
    );
    final dropdown = find.byType(DropdownButtonFormField<bool>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('No').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      (await setup.repository.fetchClinicalCase(
        setup.caseId,
      )).clinicianFacts[careKey],
      false,
    );
    expect(find.byType(TextFormField), findsNothing);
  });
}
