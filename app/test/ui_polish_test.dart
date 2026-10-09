import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/screens/patient_home_screen.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:csi6224_patient_feedback/widgets/pathway_action_view.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_presentation.dart';
import 'ui_polish_support.dart';

void main() {
  test(
    'saved adherence concern explains the outcome without diagnosing an example',
    () {
      final evaluation = PathwayEvaluation.fromJson({
        'pathwayId': 'PATHWAY1',
        'contractVersion': 'songyi-p1p2-20261009-adherence',
        'trace': [
          {
            'nodeId': 'ADHERENCE_CONCERN',
            'pathwayId': 'PATHWAY1',
            'nodeType': 'decision',
            'matched': true,
          },
        ],
      });
      expect(recommendationExplanation(evaluation), [
        'There is a concern about treatment adherence.',
      ]);
    },
  );
  testWidgets('adherence wording saves one explicit aggregate confirmation', (
    tester,
  ) async {
    final repo = PolishRepository(node: 'ADHERENCE_CONCERN');
    await mountPolish(
      tester,
      PathwayQuestionScreen(caseId: 'evidence-case', repository: repo),
    );
    expect(
      find.text(
        "Is there concern about the patient's ability to follow the treatment plan?",
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Examples include difficulty taking medicines as prescribed or cognitive impairment.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<bool>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.answers, {'adherenceConcern': true});
    expect(find.text('Clinician confirmation is required'), findsNothing);
  });
  testWidgets(
    'treatment and follow-up preserve their alternative care plan association',
    (tester) async {
      final action = PathwayAction.fromJson({
        'type': 'actionOptions',
        'options': [
          [
            {
              'type': 'medication',
              'medication': 'Drug A',
              'dose': '60mg',
              'route': 'subcut',
              'frequency': '6 monthly',
            },
            {'type': 'followUp', 'instruction': 'Review A'},
            {
              'type': 'review',
              'instruction': 'Reassess fracture risk after 5 years',
            },
          ],
          [
            {'type': 'medication', 'medication': 'Drug B'},
            {'type': 'followUp', 'instruction': 'Review B'},
          ],
        ],
      });
      await mountPolish(
        tester,
        Scaffold(
          body: PathwayActionView(
            action: action,
            patientSection: PatientActionSection.treatment,
          ),
        ),
      );
      expect(find.text('Drug A'), findsOneWidget);
      expect(find.text('Drug B'), findsOneWidget);
      expect(find.textContaining('Review A'), findsNothing);
      expect(
        find.textContaining('Reassess fracture risk after 5 years'),
        findsNothing,
      );
      expect(find.text('Care plan 1'), findsOneWidget);
      expect(find.text('Dose: 60 mg'), findsOneWidget);
      await mountPolish(
        tester,
        Scaffold(
          body: PathwayActionView(
            action: action,
            patientSection: PatientActionSection.followUp,
          ),
        ),
      );
      expect(find.text('Drug A'), findsNothing);
      expect(find.textContaining('Review A'), findsOneWidget);
      expect(find.textContaining('Review B'), findsOneWidget);
      expect(
        find.textContaining('Reassess fracture risk after 5 years'),
        findsOneWidget,
      );
      expect(find.text('Care plan 1'), findsOneWidget);
      expect(find.text('Care plan 2'), findsOneWidget);
    },
  );
  for (final destination in [
    'Return to Work Queue',
    'Back to Patient Overview',
  ]) {
    testWidgets('saving decision exposes $destination and uses correct route', (
      tester,
    ) async {
      final repo = PolishRepository(approved: false);
      await mountPolish(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('Work Queue')),
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open patient'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Patient overview')),
                    body: TextButton(
                      child: const Text('Review'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RecommendationReviewScreen(
                            caseId: 'evidence-case',
                            repository: repo,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open patient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text(destination), findsNothing);
      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'A saved patient message',
      );
      await tester.ensureVisible(find.text('Save decision'));
      await tester.tap(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(find.text('Decision saved.'), findsOneWidget);
      expect(find.text('A saved patient message'), findsOneWidget);
      await tester.ensureVisible(find.text(destination));
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
      expect(
        find.text(
          destination == 'Return to Work Queue'
              ? 'Work Queue'
              : 'Patient overview',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets(
    'approved patient sees completed review and can return from care plan',
    (tester) async {
      final repo = PolishRepository();
      var signOuts = 0;
      await mountPolish(
        tester,
        PatientHomeScreen(
          user: patient,
          repository: repo,
          onSignOut: () {
            signOuts++;
          },
        ),
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(
        find.text('Your questionnaire has been reviewed.'),
        findsOneWidget,
      );
      expect(
        find.text('Your responses are waiting for clinician review.'),
        findsNothing,
      );
      expect(find.text('Care plan ready'), findsOneWidget);
      await tester.tap(find.text('View care plan'));
      await tester.pumpAndSettle();
      expect(find.text('Your Bone Health Advice'), findsOneWidget);
      expect(find.text('Treatment Options'), findsOneWidget);
      expect(find.text('Message from your clinician'), findsOneWidget);
      expect(find.textContaining('Pathway'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
      await tester.tap(find.byTooltip('Sign out'));
      expect(signOuts, 1);
      await tester.ensureVisible(find.text('Return to dashboard'));
      await tester.tap(find.text('Return to dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Your Bone Health Care'), findsOneWidget);
    },
  );
  testWidgets('unreviewed submitted questionnaire still waits for review', (
    tester,
  ) async {
    await mountPolish(
      tester,
      PatientHomeScreen(
        user: patient,
        repository: PolishRepository(approved: false),
        onSignOut: () {},
      ),
    );
    expect(
      find.text('Your responses are waiting for clinician review.'),
      findsOneWidget,
    );
    expect(find.text('Your questionnaire has been reviewed.'), findsNothing);
  });
  testWidgets(
    'question keeps missing answer unset and shows secondary source',
    (tester) async {
      final repo = PolishRepository(node: 'MINIMAL_TRAUMA_FRACTURE');
      await mountPolish(
        tester,
        PathwayQuestionScreen(caseId: 'evidence-case', repository: repo),
      );
      expect(find.text('Source: Clinician confirmed'), findsOneWidget);
      expect(find.text('Select an answer'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(repo.answers, isEmpty);
      expect(find.text('Clinician confirmation is required'), findsOneWidget);
    },
  );
  testWidgets('fracture choices preserve wrist and exact excluded facts', (
    tester,
  ) async {
    final repo = PolishRepository(node: 'FRACTURE_SITE_ELIGIBLE');
    await mountPolish(
      tester,
      PathwayQuestionScreen(caseId: 'evidence-case', repository: repo),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('Hand'), findsNothing);
    await tester.tap(find.text('Wrist / forearm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.answers['fractureSite'], 'forearm');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Excluded site — hand, foot, face, or ankle').last,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Hand, foot, face, and ankle fractures are not eligible for the general minimal-trauma-fracture pathway.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foot').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.answers['fractureSite'], 'foot');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not sure').last);
    await tester.pumpAndSettle();
    expect(find.text('More information is required.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.answers['fractureSite'], 'not_sure');
  });
  for (final fixture in ['p1', 'p2']) {
    testWidgets(
      '$fixture saved decision has exits and trace retains audit identity',
      (tester) async {
        final repo = PolishRepository(fixture: fixture);
        await mountPolish(
          tester,
          RecommendationReviewScreen(caseId: 'evidence-case', repository: repo),
        );
        expect(find.text('Return to Work Queue'), findsOneWidget);
        expect(find.text('Back to Patient Overview'), findsOneWidget);
        expect(find.byTooltip('Sign out'), findsOneWidget);
        await tester.ensureVisible(find.text('View technical trace'));
        await tester.tap(find.text('View technical trace'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Next node:'), findsNothing);
        expect(find.textContaining('Next:'), findsNothing);
        expect(find.textContaining('Audit ID:'), findsWidgets);
      },
    );
  }
}
