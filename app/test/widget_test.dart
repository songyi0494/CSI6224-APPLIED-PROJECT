import 'dart:convert';
import 'dart:io';
import 'package:csi6224_patient_feedback/app.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
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
    'clinician opens the patient-submitted assessment for read-only review',
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
      await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
      await tester.pumpAndSettle();
      expect(find.text('Review assessment'), findsOneWidget);
      expect(find.text('Avery Martin'), findsOneWidget);
      expect(find.text('Selected pathway'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    },
  );
  testWidgets(
    'patient can open a blank assessment without choosing a pathway',
    (tester) async {
      final repo = repository();
      await signIn(repo, 'patient@example.test');
      await mount(tester, repo);
      await tester.tap(find.text('Start assessment'));
      await tester.pumpAndSettle();
      expect(find.text('Your assessment'), findsOneWidget);
      expect(find.text('Pathway 1'), findsNothing);
      expect(find.text('Pathway 2'), findsNothing);
      expect(find.text('Select pathway'), findsNothing);
    },
  );
  testWidgets(
    'saving a new patient draft returns and refreshes the dashboard',
    (tester) async {
      final repo = repository();
      await signIn(repo, 'patient@example.test');
      await mount(tester, repo);
      await tester.tap(find.text('Start assessment'));
      await tester.pumpAndSettle();
      final saveDraftButton = find.widgetWithText(OutlinedButton, 'Save draft');
      final formListView = find.descendant(
        of: find.byType(Form),
        matching: find.byType(ListView),
      );
      expect(formListView, findsOneWidget);
      await tester.dragUntilVisible(
        saveDraftButton,
        formListView,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(saveDraftButton);
      await tester.pumpAndSettle();
      expect(find.text('Patient Dashboard'), findsOneWidget);
      expect(find.text('Continue assessment'), findsNWidgets(2));
    },
  );
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
