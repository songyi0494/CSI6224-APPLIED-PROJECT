import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/patient_questionnaire_catalog.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/screens/patient_home_screen.dart';
import 'package:csi6224_patient_feedback/screens/questionnaire_response_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> _selectDairy(WidgetTester tester, String option) async {
  final field = find.byType(DropdownButtonFormField<bool>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

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
              (question) => question.fieldKey == 'dairyLessThan3Serves',
            )
            .type,
        QuestionType.checkbox,
      );

      final response = await repository.submitQuestionnaireResponse(
        answers: const {
          'sex': 'Female',
          'postmenopausal': 'Yes',
          'dairyLessThan3Serves': true,
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

  test(
    'patient UI has four controls while the five-key contract is preserved',
    () {
      expect(patientQuestionnaireVisibleKeys, hasLength(4));
      expect(patientQuestionnaireVisibleKeys, {
        'postmenopausal',
        'dairyLessThan3Serves',
        'smoking',
        'alcohol',
      });
      expect(productionQuestionnaireAnswerKeys, hasLength(25));
      expect(productionQuestionnaireAnswerKeys, contains('sex'));
      expect(
        productionQuestionnaireAnswerKeys,
        containsAll(patientQuestionnaireVisibleKeys),
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
      'dairyLessThan3Serves': true,
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

  test(
    'submission always inherits profile sex and removes hidden menopause',
    () async {
      for (final contract in <(String, String)>[
        ('male', 'Male'),
        ('another_term', 'Another term'),
      ]) {
        final repository = MockAppRepository();
        final email = '${contract.$1}@example.test';
        await repository.signUp(
          RegistrationInput(
            name: 'Profile Patient',
            email: email,
            password: 'DemoPass123!',
            role: UserRole.patient,
            dateOfBirth: DateTime(1990, 1, 1),
            sexAtBirth: contract.$1,
          ),
        );
        await repository.signIn(email: email, password: 'DemoPass123!');
        final response = await repository.submitQuestionnaireResponse(
          answers: const {
            'sex': 'Female',
            'postmenopausal': 'Yes',
            'dairyLessThan3Serves': true,
            'smoking': 'No',
            'alcohol': 'No',
          },
        );
        expect(response.answers['sex'], contract.$2);
        expect(response.answers, isNot(contains('postmenopausal')));
      }

      final femaleRepository = MockAppRepository();
      await femaleRepository.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final femaleResponse = await femaleRepository.submitQuestionnaireResponse(
        answers: const {
          'sex': 'Male',
          'postmenopausal': 'Yes',
          'dairyLessThan3Serves': true,
          'smoking': 'No',
          'alcohol': 'No',
        },
      );
      expect(femaleResponse.answers['sex'], 'Female');
      expect(femaleResponse.answers['postmenopausal'], 'Yes');
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
    expect(find.text('What is your sex?'), findsNothing);
    expect(find.text('Are you postmenopausal?'), findsOneWidget);
  });

  testWidgets('patient dashboard hides intermediate workflow and controls', (
    tester,
  ) async {
    final repository = _LiveStateRepository(
      null,
      caseStatuses: const [
        ClinicalCaseStatus.draft,
        ClinicalCaseStatus.clinicianInputRequired,
        ClinicalCaseStatus.inProgress,
        ClinicalCaseStatus.evaluated,
        ClinicalCaseStatus.awaitingReview,
        ClinicalCaseStatus.manualReview,
        ClinicalCaseStatus.withheld,
        ClinicalCaseStatus.needsMoreInfo,
        ClinicalCaseStatus.followUpArranged,
        ClinicalCaseStatus.withdrawn,
      ],
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

    expect(find.text('No assessments yet.'), findsOneWidget);
    expect(find.text('Continue current assessment'), findsNothing);
    expect(find.text('Continue assessment'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Withdraw and edit'), findsNothing);
    for (final status in ClinicalCaseStatus.values.where(
      (status) => status != ClinicalCaseStatus.approved,
    )) {
      expect(find.text(status.label), findsNothing);
    }
  });

  testWidgets('profile sex controls menopause without an editable sex field', (
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
        home: QuestionnaireResponseScreen(
          form: form,
          repository: repository,
          profileSexAtBirth: 'female',
        ),
      ),
    );

    expect(find.text('Are you postmenopausal?'), findsOneWidget);
    expect(find.text('What is your sex?'), findsNothing);
  });

  for (final profileSex in ['male', 'another_term']) {
    testWidgets('$profileSex profile hides menopause and stale hidden answer', (
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
          home: QuestionnaireResponseScreen(
            form: form,
            repository: repository,
            profileSexAtBirth: profileSex,
            initialAnswers: const {'postmenopausal': 'Yes', 'sex': 'Female'},
          ),
        ),
      );
      expect(find.text('What is your sex?'), findsNothing);
      expect(find.text('Are you postmenopausal?'), findsNothing);
    });
  }

  testWidgets(
    'patient form and review expose only profile-applicable controls',
    (tester) async {
      final repository = _CapturingQuestionnaireRepository();
      await repository.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final form = await repository.fetchQuestionnaireForm();
      await tester.pumpWidget(
        MaterialApp(
          home: QuestionnaireResponseScreen(
            repository: repository,
            form: form,
            profileSexAtBirth: 'female',
            initialAnswers: const {
              'adultFractureHistory': 'Yes',
              'fractureSite': 'Hip',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What is your sex?'), findsNothing);
      expect(find.text('Are you postmenopausal?'), findsOneWidget);
      expect(
        find.text(
          'Do you usually have fewer than 3 serves of dairy foods per day?',
        ),
        findsOneWidget,
      );
      expect(find.text('Do you currently smoke?'), findsOneWidget);
      expect(find.text('Do you currently drink alcohol?'), findsOneWidget);
      for (final question in form.questions.where(
        (question) =>
            !patientQuestionnaireVisibleKeys.contains(question.fieldKey),
      )) {
        expect(find.text(question.questionText), findsNothing);
      }
      expect(find.text('Not sure'), findsNothing);

      await _selectDropdown(tester, 0, 'Yes');
      await _selectDairy(tester, 'Yes');
      await _selectDropdown(tester, 1, 'No');
      await _selectDropdown(tester, 2, 'No');

      final review = find.widgetWithText(FilledButton, 'Review your answers');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.text('What is your sex?'), findsNothing);
      expect(find.text('Are you postmenopausal?'), findsWidgets);
      expect(
        find.text(
          'Do you usually have fewer than 3 serves of dairy foods per day?',
        ),
        findsWidgets,
      );
      expect(find.text('Do you currently smoke?'), findsWidgets);
      expect(find.text('Do you currently drink alcohol?'), findsWidgets);
      expect(find.text('Have you broken a bone as an adult?'), findsNothing);
      expect(find.text('Not sure'), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Submit questionnaire'),
      );
      await tester.pumpAndSettle();

      expect(repository.submittedAnswers, {
        'sex': 'Female',
        'postmenopausal': 'Yes',
        'dairyLessThan3Serves': true,
        'smoking': 'No',
        'alcohol': 'No',
      });
    },
  );

  testWidgets(
    'narrow patient journey acknowledges submission without exposing a case',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = MockAppRepository();
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

      final start = find.text('Start questionnaire');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await _selectDropdown(tester, 0, 'Yes');
      await _selectDairy(tester, 'Yes');
      await _selectDropdown(tester, 1, 'No');
      await _selectDropdown(tester, 2, 'No');

      final review = find.widgetWithText(FilledButton, 'Review your answers');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Submit questionnaire');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.text('Questionnaire completed'), findsWidgets);
      expect(
        find.text('Your responses have been sent for clinician review.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Return to dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('No assessments yet.'), findsOneWidget);
      expect(find.text('Continue current assessment'), findsNothing);
      expect(find.text('Continue assessment'), findsNothing);
      expect(find.text('Withdraw and edit'), findsNothing);
    },
  );
}

class _LiveStateRepository extends MockAppRepository {
  _LiveStateRepository(this.response, {this.caseStatuses});

  final QuestionnaireResponse? response;
  final List<ClinicalCaseStatus>? caseStatuses;

  @override
  bool get isMock => false;

  @override
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  }) async => response;

  @override
  Future<List<ClinicalCase>> fetchClinicalCases() async {
    final seeded = (await super.fetchClinicalCases()).single;
    return caseStatuses
            ?.map(
              (status) => ClinicalCase(
                id: 'case-${status.value}',
                patientId: seeded.patientId,
                patientName: seeded.patientName,
                input: seeded.input,
                status: status,
                revision: seeded.revision,
                updatedAt: seeded.updatedAt,
              ),
            )
            .toList(growable: false) ??
        [seeded];
  }
}

class _CapturingQuestionnaireRepository extends MockAppRepository {
  Map<String, Object?>? submittedAnswers;

  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) async {
    final response = await super.submitQuestionnaireResponse(answers: answers);
    submittedAnswers = Map<String, Object?>.from(response.answers);
    return response;
  }
}
