import 'questionnaire.dart';

const _uncertainYesNo = ['Yes', 'No', 'Not sure'];

const patientQuestionnaireVisibleKeys = <String>{
  'postmenopausal',
  'dietaryDairyServings',
  'smoking',
  'alcohol',
};

/// The complete governed production answer-key contract for the patient
/// questionnaire. The five existing live keys remain unchanged; the remaining
/// keys are the bounded mature-questionnaire extension stored in the existing
/// `questionnaire_responses.answers` JSONB object.
const productionQuestionnaireAnswerKeys = <String>{
  'sex',
  'postmenopausal',
  'menopauseTiming',
  'adultFractureHistory',
  'fractureSite',
  'fractureTiming',
  'fractureCircumstance',
  'fractureAdditionalInformation',
  'osteoporosisMedicineHistory',
  'osteoporosisMedicineName',
  'osteoporosisMedicineTiming',
  'medicineAdherenceDifficulty',
  'medicineAdherenceDifficultyDetails',
  'fallsPast12Months',
  'fearOfFalling',
  'movementRehabilitationInterest',
  'physicalActivity',
  'physicalActivityDescription',
  'smoking',
  'alcohol',
  'dietaryDairyServings',
  'myocardialInfarctionHistory',
  'myocardialInfarctionTiming',
  'strokeHistory',
  'strokeTiming',
};

/// Governed mature-question definitions retained for historical answer
/// readability and internal contract compatibility. They are not part of the
/// Phase 1 patient questionnaire UI.
const maturePatientQuestions = <QuestionnaireQuestion>[
  QuestionnaireQuestion(
    id: 'B03',
    fieldKey: 'adultFractureHistory',
    questionText: 'Have you broken a bone as an adult?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 20,
    section: 'Fracture history',
    helperText:
        'Please include any break, even if you are unsure how it happened.',
  ),
  QuestionnaireQuestion(
    id: 'fracture-site',
    fieldKey: 'fractureSite',
    questionText: 'Where was the fracture?',
    type: QuestionType.singleChoice,
    options: [
      'Hip',
      'Spine or back',
      'Wrist or forearm',
      'Upper arm or shoulder',
      'Pelvis',
      'Ribs',
      'Leg, ankle or foot',
      'Other',
      'Not sure',
    ],
    displayOrder: 21,
    section: 'Fracture history',
    visibleWhenKey: 'adultFractureHistory',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'fracture-date',
    fieldKey: 'fractureTiming',
    questionText: 'About when did the fracture happen?',
    type: QuestionType.text,
    displayOrder: 22,
    section: 'Fracture history',
    visibleWhenKey: 'adultFractureHistory',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'fracture-circumstance',
    fieldKey: 'fractureCircumstance',
    questionText: 'What happened when you broke the bone?',
    type: QuestionType.text,
    displayOrder: 23,
    section: 'Fracture history',
    visibleWhenKey: 'adultFractureHistory',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'fracture-comment',
    fieldKey: 'fractureAdditionalInformation',
    questionText:
        'Anything else you would like your clinician to know about the fracture?',
    type: QuestionType.text,
    isRequired: false,
    displayOrder: 24,
    section: 'Fracture history',
    visibleWhenKey: 'adultFractureHistory',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'B07',
    fieldKey: 'osteoporosisMedicineHistory',
    questionText:
        'Are you taking any medicine for osteoporosis now, or have you taken one before?',
    type: QuestionType.singleChoice,
    options: ['Now', 'Before', 'Both', 'Never', 'Not sure'],
    displayOrder: 30,
    section: 'Osteoporosis treatment',
    helperText: 'Your care team will check this against your health records.',
  ),
  QuestionnaireQuestion(
    id: 'B08_MEDICINE_NAME',
    fieldKey: 'osteoporosisMedicineName',
    questionText: 'What is the medicine called?',
    type: QuestionType.text,
    displayOrder: 31,
    section: 'Osteoporosis treatment',
    visibleWhenKey: 'osteoporosisMedicineHistory',
    visibleWhenValues: ['Now', 'Before', 'Both'],
  ),
  QuestionnaireQuestion(
    id: 'B08_TIMELINE',
    fieldKey: 'osteoporosisMedicineTiming',
    questionText: 'About when did you take it?',
    type: QuestionType.text,
    displayOrder: 32,
    section: 'Osteoporosis treatment',
    visibleWhenKey: 'osteoporosisMedicineHistory',
    visibleWhenValues: ['Now', 'Before', 'Both'],
  ),
  QuestionnaireQuestion(
    id: 'B09',
    fieldKey: 'medicineAdherenceDifficulty',
    questionText:
        'Has anything made it difficult to take this medicine as planned?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 33,
    section: 'Osteoporosis treatment',
    visibleWhenKey: 'osteoporosisMedicineHistory',
    visibleWhenValues: ['Now', 'Before', 'Both'],
    helperText: 'This helps us understand your experience.',
  ),
  QuestionnaireQuestion(
    id: 'B09_REASON',
    fieldKey: 'medicineAdherenceDifficultyDetails',
    questionText: 'Would you like to tell us what made it difficult?',
    type: QuestionType.text,
    isRequired: false,
    displayOrder: 34,
    section: 'Osteoporosis treatment',
    visibleWhenKey: 'medicineAdherenceDifficulty',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'B10',
    fieldKey: 'fallsPast12Months',
    questionText: 'How many times have you fallen in the past 12 months?',
    type: QuestionType.numeric,
    displayOrder: 40,
    section: 'Falls and movement',
  ),
  QuestionnaireQuestion(
    id: 'B11',
    fieldKey: 'fearOfFalling',
    questionText: 'Are you worried about falling?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 41,
    section: 'Falls and movement',
  ),
  QuestionnaireQuestion(
    id: 'B12',
    fieldKey: 'movementRehabilitationInterest',
    questionText:
        'Would you like to discuss help with movement, balance or rehabilitation?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 42,
    section: 'Falls and movement',
    helperText: 'Your clinician can discuss available support.',
  ),
  QuestionnaireQuestion(
    id: 'B13',
    fieldKey: 'physicalActivity',
    questionText: 'Are you currently doing any physical activity?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 50,
    section: 'Lifestyle',
  ),
  QuestionnaireQuestion(
    id: 'B13_COMMENT',
    fieldKey: 'physicalActivityDescription',
    questionText: 'Would you like to describe your physical activity?',
    type: QuestionType.text,
    isRequired: false,
    displayOrder: 51,
    section: 'Lifestyle',
    visibleWhenKey: 'physicalActivity',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'B16',
    fieldKey: 'myocardialInfarctionHistory',
    questionText:
        'Have you ever been told by a doctor that you had a heart attack?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 70,
    section: 'Medical history',
    helperText: 'Some treatment options depend on this history.',
  ),
  QuestionnaireQuestion(
    id: 'B16_DATE',
    fieldKey: 'myocardialInfarctionTiming',
    questionText: 'About when did the heart attack happen?',
    type: QuestionType.text,
    isRequired: false,
    displayOrder: 71,
    section: 'Medical history',
    visibleWhenKey: 'myocardialInfarctionHistory',
    visibleWhenValues: ['Yes'],
  ),
  QuestionnaireQuestion(
    id: 'B17',
    fieldKey: 'strokeHistory',
    questionText: 'Have you ever been told by a doctor that you had a stroke?',
    type: QuestionType.singleChoice,
    options: _uncertainYesNo,
    displayOrder: 72,
    section: 'Medical history',
    helperText: 'Some treatment options depend on this history.',
  ),
  QuestionnaireQuestion(
    id: 'B17_DATE',
    fieldKey: 'strokeTiming',
    questionText: 'About when did the stroke happen?',
    type: QuestionType.text,
    isRequired: false,
    displayOrder: 73,
    section: 'Medical history',
    visibleWhenKey: 'strokeHistory',
    visibleWhenValues: ['Yes'],
  ),
];

QuestionnaireForm buildMaturePatientForm(List<QuestionnaireQuestion> system) {
  QuestionnaireQuestion? byKey(String key) {
    for (final question in system) {
      if (question.fieldKey == key) return question;
    }
    return null;
  }

  QuestionnaireQuestion systemQuestion(
    String key,
    String fallbackText,
    QuestionType type,
    List<String> allowedOptions,
    int order, {
    String section = 'About you',
    String? visibleWhenKey,
    List<Object?> visibleWhenValues = const [],
  }) {
    final live = byKey(key);
    final liveOptions = live?.options
        .where(allowedOptions.contains)
        .toList(growable: false);
    return QuestionnaireQuestion(
      id: live?.id ?? 'system-$key',
      fieldKey: key,
      questionText: live?.questionText ?? fallbackText,
      type: type,
      options: liveOptions?.isNotEmpty == true ? liveOptions! : allowedOptions,
      isRequired: live?.isRequired ?? true,
      displayOrder: order,
      createdBy: live?.createdBy,
      section: section,
      visibleWhenKey: visibleWhenKey,
      visibleWhenValues: visibleWhenValues,
    );
  }

  return QuestionnaireForm(
    displayTitle: 'Bone Health Questionnaire',
    questions: [
      systemQuestion(
        'sex',
        'What is your sex?',
        QuestionType.singleChoice,
        const ['Female', 'Male'],
        1,
      ),
      systemQuestion(
        'postmenopausal',
        'Have you gone through menopause?',
        QuestionType.singleChoice,
        const ['Yes', 'No'],
        2,
        visibleWhenKey: 'sex',
        visibleWhenValues: const ['Female'],
      ),
      const QuestionnaireQuestion(
        id: 'B15_YEAR',
        fieldKey: 'menopauseTiming',
        questionText: 'About when did you go through menopause?',
        type: QuestionType.text,
        displayOrder: 3,
        section: 'About you',
        visibleWhenKey: 'postmenopausal',
        visibleWhenValues: ['Yes'],
      ),
      ...maturePatientQuestions.take(5),
      ...maturePatientQuestions.skip(5).take(9),
      systemQuestion(
        'smoking',
        'Do you currently smoke?',
        QuestionType.singleChoice,
        const ['Yes', 'No'],
        52,
        section: 'Lifestyle',
      ),
      systemQuestion(
        'alcohol',
        'Do you currently drink alcohol?',
        QuestionType.singleChoice,
        const ['Yes', 'No'],
        53,
        section: 'Lifestyle',
      ),
      systemQuestion(
        'dietaryDairyServings',
        'Do you have fewer than 3 serves of dairy per day?',
        QuestionType.singleChoice,
        const ['Yes', 'No'],
        54,
        section: 'Lifestyle',
      ),
      ...maturePatientQuestions.skip(14),
    ],
  );
}
