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

const bmdKey = 'tScoreAtOrBelowMinus2_5AnySite';
const riskKey = 'veryHighFractureRisk';
const riskHelper =
    'T-score ≤ -3.0, plus at least one of: recent fracture within 2 years, two or more fractures, relevant clinical risk factors, FRAX major risk ≥30%, or FRAX hip risk ≥4.5%.';
Future<({MockAppRepository repository, String caseId})> atBmd() async {
  final setup = await clinicianCase();
  for (final entry in <String, Object>{
    'eGFR': true,
    'osteoporosisTreatmentStatus': false,
    'frailtyResidentialOrLimitedLifeExpectancy': false,
    'adherenceConcern': false,
    'testAvailability': true,
  }.entries) {
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: entry.key,
      value: entry.value,
    );
  }
  return setup;
}

Future<void> answer(WidgetTester tester, bool value) async {
  final control = find.byType(DropdownButtonFormField<bool>);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value ? 'Yes' : 'No').last);
  await tester.pumpAndSettle();
  final next = find.widgetWithText(FilledButton, 'Next');
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'models do not derive new authority from historical raw or partial facts',
    () {
      final input = ClinicalInput.fromFacts({
        'T-score': -3.1,
        'highRisk': true,
      });
      expect(input.tScoreAtOrBelowMinus2_5AnySite, isNull);
      expect(input.veryHighFractureRisk, isNull);
      final old = Pathway1ClinicianInput.fromJson({
        'tScoreValue': -3.1,
        'clinicianConfirmedVeryHighRisk': true,
      });
      expect(old.toEvaluatorFacts().containsKey(bmdKey), isFalse);
      expect(old.toEvaluatorFacts().containsKey(riskKey), isFalse);
      expect(old.toEvaluatorFacts().containsKey('T-score'), isFalse);
      expect(old.toEvaluatorFacts().containsKey('highRisk'), isFalse);
      final fresh = const Pathway1ClinicianInput(
        tScoreAtOrBelowMinus2_5AnySite: true,
        veryHighFractureRisk: false,
      ).toEvaluatorFacts();
      expect(fresh[bmdKey], true);
      expect(fresh[riskKey], false);
    },
  );
  test(
    'registry has two distinct P1 Booleans and preserves P2 strict lowBMD',
    () {
      for (final key in [bmdKey, riskKey, 'lowBMD']) {
        expect(pathwayFactRegistry[key]!.kind, PathwayFactKind.boolean);
      }
      expect(
        pathwayFactRegistry[bmdKey]!.helperText,
        'Femoral neck, hip, or lumbar spine.',
      );
      expect(pathwayFactRegistry[riskKey]!.helperText, riskHelper);
      expect(
        pathwayFactRegistry['lowBMD']!.label,
        'BMD T-score below -3.0 at any site',
      );
      for (final key in [
        'femoralNeckTscore',
        'hipTscore',
        'lumbarSpineTscore',
        'recentFractureWithin2Y',
        'historyOf2orMoreFractures',
        'clinicalRiskFactors',
        'FRAX10YmajorOsteoporoticFractureRiskPercent',
        'FRAX10YmajorHipFractureRiskPercent',
      ]) {
        expect(pathwayFactRegistry.containsKey(key), isFalse);
      }
    },
  );
  test(
    'A/B: mock T-score true and false select their corresponding branches',
    () async {
      for (final value in [true, false]) {
        final setup = await atBmd();
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: bmdKey,
          value: value,
        );
        final result = await setup.repository.evaluatePathway(
          caseId: setup.caseId,
        );
        if (value) {
          expect(result, isA<PathwayQuestionStep>());
          expect(
            (result as PathwayQuestionStep).nodeId,
            'RECENT_MAJOR_FRACTURES',
          );
        } else {
          expect(result, isA<CompletedPathwayEvaluation>());
          expect(
            result.trace.lastWhere((t) => t.nodeId == 'T_SCORE_CHECK').matched,
            false,
          );
        }
      }
    },
  );
  test('C: missing T-score is requested without a false default', () async {
    final setup = await atBmd();
    final result =
        await setup.repository.evaluatePathway(caseId: setup.caseId)
            as PathwayQuestionStep;
    expect(result.requiredFacts, [bmdKey]);
    expect(result.helperText, 'Femoral neck, hip, or lumbar spine.');
  });
  test(
    'D/E/F: mock complete-risk true, false and missing remain distinct',
    () async {
      for (final value in <bool?>[true, false, null]) {
        final setup = await atBmd();
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: bmdKey,
          value: true,
        );
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'hipVertebralOrMultipleFracturesInLast24M',
          value: false,
        );
        if (value != null) {
          await setup.repository.savePathwayAnswer(
            caseId: setup.caseId,
            fieldKey: riskKey,
            value: value,
          );
        }
        final result = await setup.repository.evaluatePathway(
          caseId: setup.caseId,
        );
        if (value == null) {
          expect((result as PathwayQuestionStep).requiredFacts, [riskKey]);
          expect(result.helperText, riskHelper);
        } else {
          expect(result, isA<CompletedPathwayEvaluation>());
          expect(
            result.trace
                .lastWhere((t) => t.nodeId == 'HIGH_RISK_CHECK')
                .matched,
            value,
          );
        }
      }
    },
  );
  test(
    'numeric and uncertain confirmations and obsolete component writes are rejected',
    () async {
      final setup = await atBmd();
      for (final key in [bmdKey, riskKey]) {
        for (final value in [-3.1, 30, 'not_sure', 'true']) {
          await expectLater(
            setup.repository.savePathwayAnswer(
              caseId: setup.caseId,
              fieldKey: key,
              value: value,
            ),
            throwsA(isA<AppException>()),
          );
        }
      }
      await expectLater(
        setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'hipTscore',
          value: -3.1,
        ),
        throwsA(isA<AppException>()),
      );
    },
  );
  test(
    'trace labels identify current Booleans while predecessor snapshots stay historical',
    () {
      for (final node in ['T_SCORE_CHECK', 'HIGH_RISK_CHECK']) {
        final current = ReasoningTraceEntry.fromJson({
          'pathwayId': 'PATHWAY1',
          'nodeId': node,
          'nodeType': 'decision',
          'matched': true,
          'contractVersion': 'songyi-p1p2-20261009-bmd',
        });
        expect(
          clinicalTracePresentation(current).details.single,
          contains('= Yes'),
        );
        final old = ReasoningTraceEntry.fromJson({
          'pathwayId': 'PATHWAY1',
          'nodeId': node,
          'nodeType': 'decision',
          'matched': true,
          'contractVersion': 'songyi-p1p2-20261008',
        });
        expect(
          clinicalTracePresentation(old).details.single,
          contains('Historical component-based decision'),
        );
      }
    },
  );
  testWidgets('T-score screen uses one Boolean and shows OR site helper', (
    tester,
  ) async {
    final setup = await atBmd();
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
      find.text('Is the T-score -2.5 or lower at any of these sites?'),
      findsWidgets,
    );
    expect(find.text('Femoral neck, hip, or lumbar spine.'), findsOneWidget);
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
      )).clinicianFacts.containsKey(bmdKey),
      false,
    );
  });
  testWidgets(
    'very-high-risk helper contains the full composite and fits a 414 pixel screen',
    (tester) async {
      tester.view.physicalSize = const Size(414, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final setup = await atBmd();
      await tester.pumpWidget(
        MaterialApp(
          home: PathwayQuestionScreen(
            caseId: setup.caseId,
            repository: setup.repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await answer(tester, true);
      await answer(tester, false);
      expect(find.text(riskHelper), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      // Allow the test framework to report any layout error with its widget context.
      expect(
        (await setup.repository.fetchClinicalCase(
          setup.caseId,
        )).clinicianFacts.containsKey(riskKey),
        false,
      );
    },
  );
}
