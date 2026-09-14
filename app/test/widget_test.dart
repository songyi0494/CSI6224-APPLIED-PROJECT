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

Finder formListView() => find.descendant(
  of: find.byType(Form),
  matching: find.byType(ListView),
);

Future<void> tapFormAction(WidgetTester tester, Finder target) async {
  final scrollable = formListView();
  expect(scrollable, findsOneWidget);
  await tapVisible(tester, target, scrollable);
}

Future<void> tapReviewAction(WidgetTester tester, Finder target) async {
  await tapVisible(tester, target, find.byType(ListView).last);
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
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Enter clinical input'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review assessment'), findsOneWidget);
      expect(find.text('Avery Martin'), findsOneWidget);
      expect(find.text('Selected pathway'), findsOneWidget);
      expect(find.text('Clinician clinical input'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    },
  );
  testWidgets(
    'patient continues the active assessment without choosing a pathway',
    (tester) async {
      final repo = repository();
      await signIn(repo, 'patient@example.test');
      await mount(tester, repo);
      expect(find.text('Start assessment'), findsNothing);
      await tester.tap(find.text('Continue current assessment'));
      await tester.pumpAndSettle();
      expect(find.text('Your assessment'), findsOneWidget);
      expect(find.text('Pathway 1'), findsNothing);
      expect(find.text('Pathway 2'), findsNothing);
      expect(find.text('Select pathway'), findsNothing);
      expect(
        find.text('Very high fracture risk recorded by a clinician'),
        findsNothing,
      );
      expect(find.text('Kidney function (eGFR)'), findsNothing);
      expect(find.text('Lowest recorded T-score'), findsNothing);
      expect(find.text('History of heart attack or stroke'), findsNothing);
    },
  );
  testWidgets(
    'saving the active patient draft returns and refreshes the dashboard',
    (tester) async {
      final repo = repository();
      await signIn(repo, 'patient@example.test');
      await mount(tester, repo);
      await tester.tap(find.text('Continue current assessment'));
      await tester.pumpAndSettle();
      final saveDraftButton = find.widgetWithText(OutlinedButton, 'Save draft');
      await tapFormAction(tester, saveDraftButton);
      expect(find.text('Patient Dashboard'), findsOneWidget);
      expect(find.text('Continue current assessment'), findsOneWidget);
      expect(find.text('Continue assessment'), findsOneWidget);
    },
  );
  testWidgets('patient reviews answers before submission', (tester) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final draft = (await repo.fetchClinicalCases()).single;

    await mount(tester, repo);
    await tester.tap(find.text('Continue current assessment'));
    await tester.pumpAndSettle();
    await tapFormAction(
      tester,
      find.widgetWithText(FilledButton, 'Review answers'),
    );

    expect(find.text('Review your assessment'), findsOneWidget);
    expect(
      find.text('Please check your answers before submitting.'),
      findsOneWidget,
    );
    final reviewed = await repo.fetchClinicalCase(draft.id);
    expect(reviewed.status, ClinicalCaseStatus.draft);
    expect(reviewed.submittedAt, isNull);
    expect(
      find.text('Have you ever taken medicine for osteoporosis?'),
      findsOneWidget,
    );
    expect(find.text('Sex at birth'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Menopause has occurred'), findsOneWidget);
    expect(find.text('Fracture after a minor fall or injury'), findsOneWidget);
    expect(find.text('Fracture site'), findsOneWidget);
    expect(find.text('Spine'), findsOneWidget);
    expect(find.text('vertebral'), findsNothing);
    expect(find.text('Lives in residential aged care'), findsOneWidget);
    expect(find.text('Kidney function (eGFR)'), findsNothing);
    expect(find.text('Clinical frailty score'), findsNothing);
    expect(find.text('Lowest recorded T-score'), findsNothing);
    expect(find.text('Confirm & submit'), findsOneWidget);
  });
  testWidgets('patient can go back, edit, and review updated answers', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final draft = (await repo.fetchClinicalCases()).single;

    await mount(tester, repo);
    await tester.tap(find.text('Continue current assessment'));
    await tester.pumpAndSettle();
    await tapFormAction(
      tester,
      find.widgetWithText(FilledButton, 'Review answers'),
    );
    await tapReviewAction(
      tester,
      find.widgetWithText(OutlinedButton, 'Back and edit'),
    );

    expect(find.text('Your assessment'), findsOneWidget);
    expect(
      (await repo.fetchClinicalCase(draft.id)).status,
      ClinicalCaseStatus.draft,
    );
    await tapFormAction(tester, find.text('Spine'));
    await tester.tap(find.text('Hip').last);
    await tester.pumpAndSettle();
    await tapFormAction(
      tester,
      find.widgetWithText(FilledButton, 'Review answers'),
    );

    expect(find.text('Review your assessment'), findsOneWidget);
    expect(find.text('Hip'), findsOneWidget);
    expect(find.text('Spine'), findsNothing);
    expect(
      (await repo.fetchClinicalCase(draft.id)).status,
      ClinicalCaseStatus.draft,
    );
  });
  testWidgets('confirming reviewed answers submits the same assessment', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final draft = (await repo.fetchClinicalCases()).single;

    await mount(tester, repo);
    await tester.tap(find.text('Continue current assessment'));
    await tester.pumpAndSettle();
    await tapFormAction(
      tester,
      find.widgetWithText(FilledButton, 'Review answers'),
    );
    await tapReviewAction(
      tester,
      find.widgetWithText(FilledButton, 'Confirm & submit'),
    );

    final submitted = await repo.fetchClinicalCase(draft.id);
    expect(submitted.id, draft.id);
    expect(submitted.status, ClinicalCaseStatus.clinicianInputRequired);
    expect(find.text('Patient Dashboard'), findsOneWidget);
    expect(find.text('Waiting for clinician input'), findsOneWidget);
    expect(find.text('Withdraw and edit'), findsOneWidget);
    expect(await repo.fetchClinicalCases(), hasLength(1));
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
    expect(find.text('Recommendation approved'), findsOneWidget);
    expect(
      find.text(
        'Your clinician has reviewed your assessment and approved the recommendation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reviewed recommendation'), findsOneWidget);
    expect(
      find.text('Consider commencement of osteoanabolic therapy'),
      findsOneWidget,
    );
    expect(find.text('Message from your clinician'), findsOneWidget);
    expect(
      find.text('Reviewed recommendation and clinical inputs.'),
      findsOneWidget,
    );
    expect(find.text('Reviewed and approved'), findsOneWidget);

    await tapVisible(
      tester,
      find.text('View recommendation'),
      find.byType(ListView).last,
    );
    final dialog = find.byType(AlertDialog);
    Finder inDialog(Finder finder) => find.descendant(
      of: dialog,
      matching: finder,
    );

    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('Reviewed recommendation')), findsOneWidget);
    expect(
      inDialog(find.text('Consider commencement of osteoanabolic therapy')),
      findsOneWidget,
    );
    expect(
      inDialog(find.text('Reviewed recommendation and clinical inputs.')),
      findsOneWidget,
    );
    expect(inDialog(find.textContaining('Pathway 1')), findsNothing);
    expect(inDialog(find.textContaining('PATHWAY1')), findsNothing);
    expect(inDialog(find.textContaining('Treatment naïve')), findsNothing);
    expect(inDialog(find.textContaining('ENTRY')), findsNothing);
    expect(inDialog(find.textContaining('T_SCORE')), findsNothing);
    expect(
      inDialog(find.textContaining('RECENT_MAJOR_FRACTURES')),
      findsNothing,
    );
    expect(inDialog(find.textContaining('rule version')), findsNothing);
    expect(inDialog(find.textContaining('rule_version')), findsNothing);
    expect(inDialog(find.textContaining('Rule version')), findsNothing);
    expect(inDialog(find.textContaining('Technical rule')), findsNothing);
  });
  testWidgets('patient more information outcome is patient friendly', (
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
      decision: ClinicalCaseStatus.needsMoreInfo,
      notes: 'Please confirm when the fracture occurred.',
    );

    await signIn(repo, 'patient@example.test');
    await mount(tester, repo);

    expect(find.text('More information needed'), findsWidgets);
    expect(
      find.text(
        'Your clinician needs some additional information before completing your assessment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Message from your clinician'), findsOneWidget);
    expect(
      find.text('Please confirm when the fracture occurred.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Please follow the instructions from your clinician before the assessment can be completed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('needs_more_information'), findsNothing);
    expect(find.text('Provide more information'), findsNothing);
    expect(find.text('Continue assessment'), findsNothing);
    expect(find.text('Continue current assessment'), findsNothing);
    expect(find.text('Assessment in progress'), findsOneWidget);
  });
  testWidgets('patient follow-up outcome is patient friendly', (tester) async {
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
      decision: ClinicalCaseStatus.followUpArranged,
      notes: 'Please book a follow-up appointment after your blood tests.',
    );

    await signIn(repo, 'patient@example.test');
    await mount(tester, repo);

    expect(find.text('Follow-up arranged'), findsOneWidget);
    expect(
      find.text(
        'Your clinician has recommended follow-up before the assessment is complete.',
      ),
      findsOneWidget,
    );
    expect(find.text('Follow-up details'), findsOneWidget);
    expect(
      find.text(
        'Please book a follow-up appointment after your blood tests.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Please follow the instructions from your clinician for the next step.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('follow_up_required'), findsNothing);
    expect(find.textContaining('arrange_follow_up'), findsNothing);
  });
  testWidgets('patient can withdraw submitted assessment before editing', (
    tester,
  ) async {
    final repo = repository();
    await signIn(repo, 'patient@example.test');
    final a = (await repo.fetchClinicalCases()).single;
    final submitted = await repo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    await mount(tester, repo);
    expect(find.text('Waiting for clinician input'), findsOneWidget);
    expect(find.text('Assessment in progress'), findsOneWidget);
    expect(find.text('Continue current assessment'), findsNothing);
    expect(find.text('Withdraw and edit'), findsOneWidget);

    await tester.tap(find.text('Withdraw and edit'));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw submission?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await repo.fetchClinicalCase(submitted.id)).status,
      ClinicalCaseStatus.clinicianInputRequired,
    );

    await tester.tap(find.text('Withdraw and edit'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Withdraw and edit').last,
    );
    await tester.pumpAndSettle();
    final draft = await repo.fetchClinicalCase(submitted.id);
    expect(draft.status, ClinicalCaseStatus.draft);
    expect(draft.input.toFacts(), submitted.input.toFacts());
    expect(find.text('Continue current assessment'), findsOneWidget);
    expect(find.text('Continue assessment'), findsOneWidget);

    await tester.tap(find.text('Continue assessment'));
    await tester.pumpAndSettle();
    expect(find.text('Your assessment'), findsOneWidget);
    expect(find.text('Spine'), findsOneWidget);
    await tapFormAction(tester, find.text('Spine'));
    await tester.tap(find.text('Hip').last);
    await tester.pumpAndSettle();
    await tapFormAction(
      tester,
      find.widgetWithText(FilledButton, 'Review answers'),
    );
    expect(find.text('Review your assessment'), findsOneWidget);
    expect(find.text('Hip'), findsOneWidget);
    await tapReviewAction(
      tester,
      find.widgetWithText(FilledButton, 'Confirm & submit'),
    );

    final resubmitted = await repo.fetchClinicalCase(submitted.id);
    expect(resubmitted.id, submitted.id);
    expect(resubmitted.status, ClinicalCaseStatus.clinicianInputRequired);
    expect(resubmitted.input.fractureSite, 'hip');
    expect(await repo.fetchClinicalCases(), hasLength(1));
    expect(find.text('Waiting for clinician input'), findsOneWidget);
    expect(find.text('Withdraw and edit'), findsOneWidget);
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
