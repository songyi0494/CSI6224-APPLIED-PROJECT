import 'package:csi6224_patient_feedback/app.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/screens/questionnaire_response_screen.dart';
import 'package:csi6224_patient_feedback/screens/questionnaire_submitted_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _signIn(MockAppRepository repository, String email) =>
    repository.signIn(email: email, password: 'DemoPass123!');

Future<void> _selectDropdown(
  WidgetTester tester,
  int index,
  String option,
) async {
  final dropdown = find.byType(DropdownButtonFormField<String>).at(index);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('patient completes questionnaire and sees confirmation', (
    tester,
  ) async {
    final repository = MockAppRepository();
    await _signIn(repository, 'patient@example.test');
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionnaireResponseScreen(
          repository: repository,
          form: const QuestionnaireForm(
            questions: [
              QuestionnaireQuestion(
                id: 'system-smoking-row',
                fieldKey: 'smoking',
                questionText: 'Do you currently smoke?',
                type: QuestionType.singleChoice,
                options: ['Yes', 'No', 'Not sure'],
                displayOrder: 1,
                section: 'Lifestyle',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectDropdown(tester, 0, 'No');
    final review = find.widgetWithText(FilledButton, 'Review your answers');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Review your answers'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Submit questionnaire'));
    await tester.pumpAndSettle();
    final response = await repository.fetchQuestionnaireResponse(
      patientId: 'patient-a',
    );
    expect(response, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: QuestionnaireSubmittedScreen(response: response!)),
    );
    await tester.pump();
    expect(find.text('Questionnaire submitted'), findsWidgets);
  });

  testWidgets(
    'clinician overview labels questionnaire answers as patient reported',
    (tester) async {
      final repository = MockAppRepository();
      await _signIn(repository, 'patient@example.test');
      await repository.submitQuestionnaireResponse(
        answers: const {
          'sex': 'Female',
          'postmenopausal': 'Yes',
          'adultFractureHistory': 'Yes',
          'fractureSite': 'Hip',
          'osteoporosisMedicineHistory': 'Before',
          'fallsPast12Months': 2,
          'physicalActivity': 'Yes',
          'myocardialInfarctionHistory': 'No',
          'dietaryDairyServings': 2,
          'smoking': 'No',
          'alcohol': 'No',
        },
      );
      final assessment = (await repository.fetchClinicalCases()).single;
      await repository.submitAssessment(
        id: assessment.id,
        revision: assessment.revision,
        input: assessment.input,
      );
      await _signIn(repository, 'clinician@example.test');
      await tester.pumpWidget(OsteoporosisPathwaysApp(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Patient-Reported Questionnaire'), findsOneWidget);
      expect(find.text('Patient reported'), findsWidgets);
      expect(find.text('Do you currently smoke?'), findsWidgets);
      expect(find.text('No'), findsWidgets);
      expect(find.text('Have you broken a bone as an adult?'), findsOneWidget);
      expect(find.text('Where was the fracture?'), findsOneWidget);
      expect(find.text('Hip'), findsOneWidget);
      expect(
        find.text(
          'Are you taking any medicine for osteoporosis now, or have you taken one before?',
        ),
        findsOneWidget,
      );
      expect(
        find.text('How many times have you fallen in the past 12 months?'),
        findsOneWidget,
      );
      expect(
        find.text('Are you currently doing any physical activity?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Have you ever been told by a doctor that you had a heart attack?',
        ),
        findsOneWidget,
      );
      expect(find.text('Start Pathway Assessment'), findsOneWidget);
    },
  );
}
