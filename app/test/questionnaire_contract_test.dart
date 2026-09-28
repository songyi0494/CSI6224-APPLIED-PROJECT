import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/models/patient_questionnaire_catalog.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/screens/patient_home_screen.dart';
import 'package:csi6224_patient_feedback/screens/questionnaire_response_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live question types and answer-key identities remain distinct', () {
    expect(QuestionType.values.map((type) => type.databaseValue), [
      'text',
      'numeric',
      'checkbox',
      'single_choice',
      'multi_choice',
      'dropdown',
      'scale',
    ]);

    const systemQuestion = QuestionnaireQuestion(
      id: 'database-row-id',
      fieldKey: 'smoking',
      questionText: 'Do you currently smoke?',
      type: QuestionType.singleChoice,
      options: ['Yes', 'No'],
      displayOrder: 4,
    );
    const customQuestion = QuestionnaireQuestion(
      id: 'custom-row-id',
      questionText: 'Custom question',
      type: QuestionType.text,
      displayOrder: 6,
    );

    expect(systemQuestion.productionAnswerKey, 'smoking');
    expect(systemQuestion.productionAnswerKey, isNot(systemQuestion.id));
    expect(customQuestion.productionAnswerKey, isNull);
    expect(customQuestion.mockUiAnswerKey, 'mock-custom:custom-row-id');
  });

  test(
    'mature questionnaire exposes one governed production key per question',
    () async {
      final repository = MockAppRepository();
      await repository.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );

      final form = await repository.fetchQuestionnaireForm();

      expect(
        form.questions,
        hasLength(productionQuestionnaireAnswerKeys.length),
      );
      expect(
        form.questions.map((question) => question.fieldKey).toSet(),
        productionQuestionnaireAnswerKeys,
      );
      expect(
        form.questions.map((question) => question.id),
        containsAll(['B03', 'B07', 'B10', 'B11', 'B12', 'B13', 'B16', 'B17']),
      );
      expect(
        form.orderedQuestions
            .firstWhere(
              (question) => question.fieldKey == 'dietaryDairyServings',
            )
            .type,
        QuestionType.numeric,
      );

      final response = await repository.submitQuestionnaireResponse(
        answers: const {
          'sex': 'Female',
          'postmenopausal': 'Yes',
          'dietaryDairyServings': 2,
          'smoking': 'No',
          'alcohol': 'No',
        },
      );
      expect(response.status, QuestionnaireResponseStatus.submitted);
      expect(response.patientId, 'patient-a');
      expect(response.answers.keys, contains('smoking'));
      expect(response.answers.keys, isNot(contains('system-smoking-row')));
      expect(
        await repository.fetchQuestionnaireResponse(patientId: 'patient-a'),
        same(response),
      );
    },
  );

  test('governed production mapping preserves system and mature answers', () {
    const answers = <String, Object?>{
      'sex': 'Female',
      'postmenopausal': 'Yes',
      'menopauseTiming': 'Around 2010',
      'adultFractureHistory': 'Yes',
      'fractureSite': 'Hip',
      'osteoporosisMedicineHistory': 'Before',
      'osteoporosisMedicineName': 'Patient-entered medicine',
      'fallsPast12Months': 2,
      'physicalActivity': 'Yes',
      'myocardialInfarctionHistory': 'No',
      'strokeHistory': 'No',
      'smoking': 'No',
      'alcohol': 'No',
      'dietaryDairyServings': 2,
    };

    expect(
      SupabaseAppRepository.governedQuestionnaireAnswers(answers),
      answers,
    );
  });

  test(
    'governed production mapping rejects rather than drops unknown keys',
    () {
      expect(
        () => SupabaseAppRepository.governedQuestionnaireAnswers(const {
          'sex': 'Female',
          'unapprovedUiOnlyKey': 'must not disappear silently',
        }),
        throwsA(isA<AppException>()),
      );
    },
  );

  testWidgets('draft response is resumable and is not displayed as submitted', (
    tester,
  ) async {
    final repository = _LiveStateRepository(
      const QuestionnaireResponse(
        id: 'response-draft',
        patientId: 'patient-a',
        status: QuestionnaireResponseStatus.draft,
        revision: 1,
        answers: {'sex': 'Female'},
      ),
    );
    final user = await repository.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PatientHomeScreen(
          user: user,
          repository: repository,
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Submitted'), findsNothing);
    expect(find.text('Resume questionnaire'), findsOneWidget);

    await tester.tap(find.text('Resume questionnaire'));
    await tester.pumpAndSettle();
    expect(find.text('Female'), findsWidgets);
  });

  testWidgets('live waiting case is explicit and hides unsupported withdraw', (
    tester,
  ) async {
    final repository = _LiveStateRepository(null);
    final user = await repository.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final draft = (await repository.fetchClinicalCases()).single;
    await repository.submitAssessment(
      id: draft.id,
      revision: draft.revision,
      input: draft.input,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PatientHomeScreen(
          user: user,
          repository: repository,
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Submitted — waiting for clinician'), findsOneWidget);
    expect(find.text('Submitted — waiting for clinician.'), findsOneWidget);
    expect(find.text('Withdraw and edit'), findsNothing);
  });

  testWidgets('sex controls menopause visibility without inferring an answer', (
    tester,
  ) async {
    final repository = MockAppRepository();
    await repository.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final form = await repository.fetchQuestionnaireForm();

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionnaireResponseScreen(form: form, repository: repository),
      ),
    );

    expect(find.text('Are you postmenopausal?'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    expect(find.text('Are you postmenopausal?'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last);
    await tester.pumpAndSettle();

    expect(find.text('Are you postmenopausal?'), findsNothing);
  });

  testWidgets('unsupported multi-choice questions fail visibly', (
    tester,
  ) async {
    final repository = MockAppRepository();
    await repository.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionnaireResponseScreen(
          repository: repository,
          form: const QuestionnaireForm(
            questions: [
              QuestionnaireQuestion(
                id: 'custom-row',
                questionText: 'Choose several options',
                type: QuestionType.multiChoice,
                options: ['A', 'B'],
                displayOrder: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Multiple-choice input is not supported in this UI yet.'),
      findsOneWidget,
    );
  });

  testWidgets('hidden conditional answers are absent from review and payload', (
    tester,
  ) async {
    final repository = _CapturingQuestionnaireRepository();
    await repository.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionnaireResponseScreen(
          repository: repository,
          form: const QuestionnaireForm(
            questions: [
              QuestionnaireQuestion(
                id: 'fracture-parent',
                fieldKey: 'adultFractureHistory',
                questionText: 'Have you broken a bone as an adult?',
                type: QuestionType.singleChoice,
                options: ['Yes', 'No'],
                displayOrder: 1,
              ),
              QuestionnaireQuestion(
                id: 'fracture-child',
                fieldKey: 'fractureSite',
                questionText: 'Where was the fracture?',
                type: QuestionType.singleChoice,
                options: ['Hip', 'Wrist'],
                displayOrder: 2,
                visibleWhenKey: 'adultFractureHistory',
                visibleWhenValues: ['Yes'],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hip').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('No').last);
    await tester.pumpAndSettle();
    expect(find.text('Where was the fracture?'), findsNothing);

    final review = find.widgetWithText(FilledButton, 'Review your answers');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Have you broken a bone as an adult?'), findsWidgets);
    expect(find.text('Where was the fracture?'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Submit questionnaire'));
    await tester.pumpAndSettle();

    expect(repository.submittedAnswers, {'adultFractureHistory': 'No'});
  });
}

class _LiveStateRepository extends MockAppRepository {
  _LiveStateRepository(this.response);

  final QuestionnaireResponse? response;

  @override
  bool get isMock => false;

  @override
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  }) async => response;
}

class _CapturingQuestionnaireRepository extends MockAppRepository {
  Map<String, Object?>? submittedAnswers;

  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) async {
    submittedAnswers = Map<String, Object?>.from(answers);
    return super.submitQuestionnaireResponse(answers: answers);
  }
}
