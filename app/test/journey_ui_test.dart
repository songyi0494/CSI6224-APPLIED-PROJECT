import 'package:csi6224_patient_feedback/app.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/patient_questionnaire_catalog.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
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
          profileSexAtBirth: 'female',
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
    'clinician overview shows only five patient answers and unavailable age',
    (tester) async {
      final repository = MockAppRepository();
      await _signIn(repository, 'patient@example.test');
      await repository.submitQuestionnaireResponse(
        answers: const {
          'sex': 'Female',
          'postmenopausal': 'Yes',
          'menopauseTiming': 'Around 2010',
          'adultFractureHistory': 'Yes',
          'fractureSite': 'Hip',
          'fractureTiming': '2020',
          'fractureCircumstance': 'Fall',
          'fractureAdditionalInformation': 'Historical detail',
          'osteoporosisMedicineHistory': 'Before',
          'osteoporosisMedicineName': 'Historical medicine',
          'osteoporosisMedicineTiming': '2019',
          'medicineAdherenceDifficulty': 'Yes',
          'medicineAdherenceDifficultyDetails': 'Historical detail',
          'fallsPast12Months': 2,
          'fearOfFalling': 'Yes',
          'movementRehabilitationInterest': 'Yes',
          'physicalActivity': 'Yes',
          'physicalActivityDescription': 'Walking',
          'myocardialInfarctionHistory': 'No',
          'myocardialInfarctionTiming': 'Not applicable',
          'strokeHistory': 'No',
          'strokeTiming': 'Not applicable',
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
      expect(find.text('Patient reported'), findsNothing);
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
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('71'), findsOneWidget);
      expect(
        find.text('About when did you go through menopause?'),
        findsNothing,
      );
      for (final hiddenQuestion in maturePatientQuestions) {
        expect(find.text(hiddenQuestion.questionText), findsNothing);
      }
      expect(find.text('Hip'), findsNothing);
      expect(find.text('Historical medicine'), findsNothing);
      for (final removedSection in const [
        'Assessment Status',
        'Lifestyle Information',
        'Relevant Clinical Information',
        'Pathway Status',
      ]) {
        expect(find.text(removedSection), findsNothing);
      }
      expect(find.text('Investigations'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget);
      expect(find.text('Start Pathway'), findsOneWidget);
    },
  );

  testWidgets('clinician overview shows N/A for absent male menopause answer', (
    tester,
  ) async {
    final repository = MockAppRepository();
    await repository.signUp(
      RegistrationInput(
        name: 'Male Patient',
        email: 'male.patient@example.test',
        password: 'DemoPass123!',
        role: UserRole.patient,
        dateOfBirth: DateTime(1960, 1, 1),
        sexAtBirth: 'male',
      ),
    );
    await _signIn(repository, 'male.patient@example.test');
    await repository.submitQuestionnaireResponse(
      answers: const {
        'dietaryDairyServings': 2,
        'smoking': 'No',
        'alcohol': 'No',
      },
    );
    await repository.submitAssessment(
      id: 'male-case',
      revision: 0,
      input: const ClinicalInput(treated: false, sexAtBirth: 'male'),
    );
    await _signIn(repository, 'clinician@example.test');
    await tester.pumpWidget(OsteoporosisPathwaysApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Postmenopausal status'), findsOneWidget);
    expect(find.text('N/A'), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
  });
}
