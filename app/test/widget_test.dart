import 'dart:convert';
import 'dart:io';
import 'package:csi6224_patient_feedback/app.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockAppRepository repository() => MockAppRepository(
  evaluate: (input) async => PathwayEvaluation.fromJson(
    jsonDecode(
          File(
            'test/fixtures/${input.treated == true ? 'pathway2' : 'pathway1'}_result.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  ),
);

const completePathway1ClinicianInput = Pathway1ClinicianInput(
  egfr: 54,
  clinicalFrailtyScore: 4,
  lifeExpectancy: 10,
  knownPoorMedicationAdherence: false,
  cognitiveImpairment: false,
  dxaDoneWithinPrevious2Years: true,
  dxaImpractical: false,
  tScoreValue: -3.5,
  tScoreSite: 'femoral_neck',
  hipVertebralOrMultipleFracturesInLast24M: true,
  yearsSinceMenopause: 20,
);

Future<void> signIn(MockAppRepository repo, String email) async {
  await repo.signIn(email: email, password: 'DemoPass123!');
}

Future<void> mount(WidgetTester tester, MockAppRepository repo) async {
  await tester.pumpWidget(OsteoporosisPathwaysApp(repository: repo));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> tapVisible(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  await tester.dragUntilVisible(target, scrollable, const Offset(0, -500));
  await tester.pumpAndSettle();
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on unified sign-in without a role selector', (
    tester,
  ) async {
    await mount(tester, repository());
    expect(find.text('OsteoCare Pathway'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    expect(find.text('Patient'), findsNothing);
    expect(find.text('Clinician'), findsNothing);
  });
  for (final entry in {
    'patient@example.test': 'Patient Dashboard',
    'clinician@example.test': 'Clinician Dashboard',
    'pending@example.test': 'Account awaiting approval',
    'rejected@example.test': 'Account not approved',
    'admin@example.test': 'Clinician approvals',
  }.entries) {
    testWidgets('profile routes ${entry.key} to ${entry.value}', (
      tester,
    ) async {
      final repo = repository();
      await signIn(repo, entry.key);
      await mount(tester, repo);
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 'pending@example.test' ||
          entry.key == 'rejected@example.test')
        expect(find.text('Clinician Dashboard'), findsNothing);
    });
  }
  testWidgets('clinician Manage opens the preserved questionnaire builder', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'clinician@example.test');
    await mount(tester, repo);
    await tester.tap(find.text('Manage questionnaires'));
    await tester.pumpAndSettle();
    expect(find.text('Questionnaire builder'), findsOneWidget);
    expect(find.text('Create questionnaire'), findsOneWidget);
  });
  testWidgets(
    'clinician opens the patient-submitted assessment for clinical input',
    (tester) async {
      final repo = repository();
      await signIn(repo, 'patient@example.test');
      final a = (await repo.fetchClinicalCases()).single;
      await repo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: a.input,
      );
      await signIn(repo, 'clinician@example.test');
      await mount(tester, repo);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Patient overview'), findsOneWidget);
      expect(find.text('Avery Martin'), findsOneWidget);
      expect(find.text('Patient-Reported Questionnaire'), findsOneWidget);
      for (final label in const [
        'Sex recorded at birth',
        'Postmenopausal status',
        'Dietary dairy servings',
        'Smoking',
        'Alcohol',
        'Age',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final removedSection in const [
        'Assessment Status',
        'Lifestyle Information',
        'Relevant Clinical Information',
        'Pathway Status',
      ]) {
        expect(find.text(removedSection), findsNothing);
      }
      expect(find.text('Patient reported'), findsNothing);
      expect(find.text('71'), findsOneWidget);
      expect(find.text('Investigations'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget);
      expect(find.text('Start Pathway'), findsOneWidget);

      await tapVisible(
        tester,
        find.text('Enter investigations'),
        find.byType(SingleChildScrollView),
      );
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
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Save'),
        find.byType(SingleChildScrollView),
      );
      expect(find.text('Completed'), findsOneWidget);
      await tapVisible(
        tester,
        find.text('Start Pathway'),
        find.byType(SingleChildScrollView),
      );
      expect(find.text('Clinical pathway'), findsOneWidget);
      expect(
        find.text("What is the patient's eGFR value? (Unit: mL/min)"),
        findsOneWidget,
      );
      expect(find.text('More clinical information required'), findsNothing);
      expect(find.text('PATHWAY1'), findsNothing);
      expect(find.text('Back'), findsNothing);
      expect(find.text('Exit pathway'), findsOneWidget);
    },
  );
  testWidgets('clinician decision choices use the existing review screen', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final assessment = (await repo.fetchClinicalCases()).single;
    await repo.submitAssessment(
      id: assessment.id,
      revision: assessment.revision,
      input: assessment.input,
    );
    await signIn(repo, 'clinician@example.test');
    await repo.completePathway1ClinicianInput(
      assessment: await repo.fetchClinicalCase(assessment.id),
      input: completePathway1ClinicianInput,
    );

    await mount(tester, repo);
    expect(find.text('Needs Review'), findsNothing);
    expect(find.text('Work Queue'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Review'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('Patient overview'), findsOneWidget);
    await tapVisible(
      tester,
      find.text('Review Result'),
      find.byType(SingleChildScrollView),
    );

    expect(find.text('Select a decision'), findsOneWidget);
    expect(find.text('Assessment Result'), findsNothing);
    expect(find.text('Pathway Result'), findsNothing);
    expect(find.text('Patient-submitted information'), findsNothing);
    expect(find.text('Clinician-entered facts'), findsNothing);
    expect(find.text('Lifestyle Recommendations'), findsNothing);
    expect(find.text('Reload assessment'), findsNothing);
    expect(find.text('Why This Result'), findsOneWidget);
    expect(find.text('Common Advice'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Withhold'), findsOneWidget);
    expect(
      find.widgetWithText(ChoiceChip, 'Request more information'),
      findsNothing,
    );
    expect(find.widgetWithText(ChoiceChip, 'Arrange follow-up'), findsNothing);

    await tapVisible(
      tester,
      find.widgetWithText(ChoiceChip, 'Withhold'),
      find.byType(SingleChildScrollView),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Withhold'))
          .selected,
      isTrue,
    );
  });
  testWidgets('patient approved result hides internal pathway terminology', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final a = (await repo.fetchClinicalCases()).single;
    await repo.submitAssessment(id: a.id, revision: a.revision, input: a.input);
    await signIn(repo, 'clinician@example.test');
    final review = await repo.completePathway1ClinicianInput(
      assessment: await repo.fetchClinicalCase(a.id),
      input: completePathway1ClinicianInput,
    );
    await repo.recordClinicianDecision(
      assessment: review,
      decision: ClinicalCaseStatus.approved,
      notes: 'Reviewed recommendation and clinical inputs.',
    );

    await signIn(repo, 'patient@example.test');
    await mount(tester, repo);
    expect(find.textContaining('Pathway 1'), findsNothing);
    expect(find.textContaining('PATHWAY1'), findsNothing);
    expect(find.textContaining('T_SCORE'), findsNothing);
    expect(find.textContaining('Rule version'), findsNothing);
    expect(
      find.text('Your clinician has approved this care recommendation.'),
      findsOneWidget,
    );
    expect(find.text('Reviewed and approved'), findsNothing);

    await tapVisible(
      tester,
      find.text('View recommendation'),
      find.byType(ListView).last,
    );
    expect(find.text('Your Care Recommendation'), findsOneWidget);
    expect(find.text('Reviewed by Your Clinician'), findsOneWidget);
    expect(find.text('Lifestyle Recommendations'), findsOneWidget);
    expect(find.text('Clinician-reviewed mock Common Advice.'), findsOneWidget);
    expect(find.text('Care Recommendation'), findsOneWidget);
    expect(
      find.text('Consider commencement of osteoanabolic therapy'),
      findsOneWidget,
    );
    expect(
      find.text('Reviewed recommendation and clinical inputs.'),
      findsOneWidget,
    );
    expect(find.text('Clinician Message'), findsOneWidget);
    expect(find.textContaining('Pathway 1'), findsNothing);
    expect(find.textContaining('PATHWAY1'), findsNothing);
    expect(find.textContaining('Treatment naïve'), findsNothing);
    expect(find.textContaining('ENTRY'), findsNothing);
    expect(find.textContaining('T_SCORE'), findsNothing);
    expect(find.textContaining('RECENT_MAJOR_FRACTURES'), findsNothing);
    expect(find.textContaining('rule version'), findsNothing);
    expect(find.textContaining('rule_version'), findsNothing);
    expect(find.textContaining('Rule version'), findsNothing);
    expect(find.textContaining('Technical rule'), findsNothing);
  });
  testWidgets('logout removes protected navigation and returns to sign-in', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    await mount(tester, repo);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(await repo.loadProfile(), isNull);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Patient Dashboard'), findsNothing);
  });
  testWidgets('invalid credentials stay on sign-in', (tester) async {
    await mount(tester, repository());
    await tester.enterText(
      find.byType(TextFormField).first,
      'unknown@example.test',
    );
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('Check your email and password and try again.'),
      findsOneWidget,
    );
  });
}
