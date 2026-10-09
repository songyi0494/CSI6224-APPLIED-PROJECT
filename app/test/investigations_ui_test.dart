import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/case_investigations.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/screens/clinician_case_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingRepository extends MockAppRepository {
  int evaluateCalls = 0;

  @override
  Future<LivePathwayResult> evaluatePathway({required String caseId}) {
    evaluateCalls += 1;
    return super.evaluatePathway(caseId: caseId);
  }
}

class _LegacyRepository extends _CountingRepository {
  bool _servedLegacy = false;

  @override
  Future<CaseInvestigations> getCaseInvestigations(String caseId) async {
    if (!_servedLegacy) {
      _servedLegacy = true;
      return CaseInvestigations(
        caseId: caseId,
        vitaminDLevel: 48,
        ionisedCalcium: 1.18,
        bodyWeightKg: 68,
        revision: 0,
        isComplete: false,
      );
    }
    return super.getCaseInvestigations(caseId);
  }
}

class _ConflictingRepository extends _CountingRepository {
  bool _conflicted = false;

  @override
  Future<CaseInvestigations> saveCaseInvestigations({
    required String caseId,
    required double? vitaminDLevel,
    required double? ionisedCalcium,
    required double? bodyWeightKg,
    required int expectedRevision,
    bool? authoritativeHypocalcaemia,
  }) async {
    if (!_conflicted) {
      _conflicted = true;
      await super.saveCaseInvestigations(
        caseId: caseId,
        vitaminDLevel: 60,
        ionisedCalcium: 1.22,
        bodyWeightKg: 75,
        expectedRevision: expectedRevision,
      );
      throw const InvestigationConflictException();
    }
    return super.saveCaseInvestigations(
      caseId: caseId,
      vitaminDLevel: vitaminDLevel,
      ionisedCalcium: ionisedCalcium,
      bodyWeightKg: bodyWeightKg,
      expectedRevision: expectedRevision,
      authoritativeHypocalcaemia: authoritativeHypocalcaemia,
    );
  }
}

Future<String> submittedCase(MockAppRepository repository) async {
  await repository.signIn(
    email: 'patient@example.test',
    password: 'DemoPass123!',
  );
  final assessment = (await repository.fetchClinicalCases()).single;
  await repository.submitAssessment(
    id: assessment.id,
    revision: assessment.revision,
    input: assessment.input,
  );
  await repository.signIn(
    email: 'clinician@example.test',
    password: 'DemoPass123!',
  );
  return assessment.id;
}

Future<void> mountCase(
  WidgetTester tester,
  MockAppRepository repository,
  String caseId,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ClinicianCaseScreen(caseId: caseId, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'claim stays on case until investigations are saved, then starts pathway',
    (tester) async {
      final repository = _CountingRepository();
      final caseId = await submittedCase(repository);
      await mountCase(tester, repository, caseId);

      expect(find.text('Patient reported'), findsOneWidget);
      expect(find.text('Investigations'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget);
      expect(repository.evaluateCalls, 0);
      expect(
        tester.getTopLeft(find.text('Patient reported')).dy,
        lessThan(tester.getTopLeft(find.text('Investigations')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Investigations')).dy,
        lessThan(tester.getTopLeft(find.text('Start Pathway')).dy),
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start Pathway'),
      );
      expect(start.onPressed, isNull);

      await tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Enter investigations'),
      );
      expect(find.text('Vitamin D level (nmol/L)'), findsOneWidget);
      expect(find.text('Ionised calcium level (mmol/L)'), findsOneWidget);
      expect(find.text('Body weight (kg)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('vitamin-d-input')),
        '55',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ionised-calcium-input')),
        '1.2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('body-weight-input')),
        '70',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));

      expect(find.text('Patient overview'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Vitamin D: 55.0 nmol/L'), findsOneWidget);
      expect(repository.evaluateCalls, 0);

      await tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Edit investigations'),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('vitamin-d-input')),
            )
            .controller!
            .text,
        '55',
      );
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Cancel'));

      final enabledStart = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start Pathway'),
      );
      expect(enabledStart.onPressed, isNotNull);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Start Pathway'),
      );
      expect(find.text('Clinical pathway'), findsOneWidget);
      expect(repository.evaluateCalls, 1);
    },
  );

  testWidgets('legacy revision zero requires explicit confirmation', (
    tester,
  ) async {
    final repository = _LegacyRepository();
    final caseId = await submittedCase(repository);
    await mountCase(tester, repository, caseId);

    expect(find.text('Requires confirmation'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Review investigations'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start Pathway'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.evaluateCalls, 0);

    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Review investigations'),
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('vitamin-d-input')))
          .controller!
          .text,
      '48',
    );
  });

  testWidgets('stale save reloads newer values and requires review', (
    tester,
  ) async {
    final repository = _ConflictingRepository();
    final caseId = await submittedCase(repository);
    await mountCase(tester, repository, caseId);
    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Enter investigations'),
    );

    await tester.enterText(find.byKey(const ValueKey('vitamin-d-input')), '55');
    await tester.enterText(
      find.byKey(const ValueKey('ionised-calcium-input')),
      '1.2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('body-weight-input')),
      '70',
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(
      find.text(
        'These investigation values were updated elsewhere. Please review the latest values before saving again.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('vitamin-d-input')))
          .controller!
          .text,
      '60',
    );
    expect(find.text('Patient overview'), findsNothing);
  });

  testWidgets('investigations workflow remains usable at a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _CountingRepository();
    final caseId = await submittedCase(repository);
    await mountCase(tester, repository, caseId);

    expect(tester.takeException(), isNull);
    expect(find.text('Investigations'), findsOneWidget);
    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Enter investigations'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Vitamin D level (nmol/L)'), findsOneWidget);
    expect(find.text('Ionised calcium level (mmol/L)'), findsOneWidget);
    expect(find.text('Body weight (kg)'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('vitamin-d-input')), '55');
    await tester.enterText(
      find.byKey(const ValueKey('ionised-calcium-input')),
      '1.2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('body-weight-input')),
      '70',
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(tester.takeException(), isNull);
    expect(find.text('Completed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start Pathway'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
