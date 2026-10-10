enum QuestionType {
  text('text'),
  numeric('numeric'),
  checkbox('checkbox'),
  singleChoice('single_choice'),
  multiChoice('multi_choice'),
  dropdown('dropdown'),
  scale('scale');

  const QuestionType(this.databaseValue);

  final String databaseValue;

  bool get requiresOptions =>
      this == singleChoice || this == multiChoice || this == dropdown;

  static QuestionType fromDatabaseValue(String value) => values.firstWhere(
    (type) => type.databaseValue == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'Unsupported questionnaire question type.',
    ),
  );
}

/// One row from global `questionnaire_questions` collection.
///
/// [id] is database row identity. [fieldKey] is stable semantic identity for
/// protected system questions. They are deliberately not interchangeable.
class QuestionnaireQuestion {
  const QuestionnaireQuestion({
    required this.id,
    required this.questionText,
    required this.type,
    required this.displayOrder,
    this.fieldKey,
    this.options = const [],
    this.isRequired = true,
    this.createdBy,
    this.section = 'About you',
    this.helperText,
    this.visibleWhenKey,
    this.visibleWhenValues = const [],
  });

  final String id;
  final String? fieldKey;
  final String questionText;
  final QuestionType type;
  final List<String> options;
  final bool isRequired;
  final int displayOrder;
  final String? createdBy;
  final String section;
  final String? helperText;
  final String? visibleWhenKey;
  final List<Object?> visibleWhenValues;

  bool get isSystemQuestion => fieldKey != null;

  String get productionAnswerKey => fieldKey ?? id;

  /// Isolated local key for widget state and mock-only custom-question demos.
  /// This value must never be persisted by the production Supabase adapter.
  String get mockUiAnswerKey => fieldKey ?? 'mock-custom:$id';

  bool isVisible(Map<String, Object?> answers) =>
      visibleWhenKey == null ||
      visibleWhenValues.contains(answers[visibleWhenKey]);

  QuestionnaireQuestion copyWith({
    String? id,
    String? fieldKey,
    bool clearFieldKey = false,
    String? questionText,
    QuestionType? type,
    List<String>? options,
    bool? isRequired,
    int? displayOrder,
    String? createdBy,
    String? section,
    String? helperText,
    String? visibleWhenKey,
    List<Object?>? visibleWhenValues,
  }) {
    return QuestionnaireQuestion(
      id: id ?? this.id,
      fieldKey: clearFieldKey ? null : fieldKey ?? this.fieldKey,
      questionText: questionText ?? this.questionText,
      type: type ?? this.type,
      options: options ?? this.options,
      isRequired: isRequired ?? this.isRequired,
      displayOrder: displayOrder ?? this.displayOrder,
      createdBy: createdBy ?? this.createdBy,
      section: section ?? this.section,
      helperText: helperText ?? this.helperText,
      visibleWhenKey: visibleWhenKey ?? this.visibleWhenKey,
      visibleWhenValues: visibleWhenValues ?? this.visibleWhenValues,
    );
  }
}

/// UI global ordered questionnaire.
class QuestionnaireForm {
  const QuestionnaireForm({
    required this.questions,
    this.displayTitle = 'Health questionnaire',
  });

  final String displayTitle;
  final List<QuestionnaireQuestion> questions;

  List<QuestionnaireQuestion> get orderedQuestions {
    final ordered = List<QuestionnaireQuestion>.of(questions)
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return List.unmodifiable(ordered);
  }
}

enum QuestionnaireResponseStatus { draft, submitted }

class QuestionnaireResponse {
  const QuestionnaireResponse({
    required this.id,
    required this.patientId,
    required this.status,
    required this.revision,
    required this.answers,
    this.submittedAt,
    this.pathwayEligible,
  });

  final String id;
  final String patientId;
  final QuestionnaireResponseStatus status;
  final int revision;
  final DateTime? submittedAt;
  final Map<String, Object?> answers;
  final bool? pathwayEligible;
}

/// Mock/UI-only container used to preserve the existing clinician builder.
/// Songyi's live backend has no questionnaire header, title, publication state,
/// or multi-questionnaire collection. Live persistence is BACKEND CONTRACT
/// PENDING and must not treat this type as a database entity.
class MockQuestionnaireDraft {
  const MockQuestionnaireDraft({
    required this.presentationId,
    required this.displayTitle,
    required this.state,
    required this.questions,
  });

  final String presentationId;
  final String displayTitle;
  final MockQuestionnaireDraftState state;
  final List<QuestionnaireQuestion> questions;

  MockQuestionnaireDraft copyWith({
    String? presentationId,
    String? displayTitle,
    MockQuestionnaireDraftState? state,
    List<QuestionnaireQuestion>? questions,
  }) {
    return MockQuestionnaireDraft(
      presentationId: presentationId ?? this.presentationId,
      displayTitle: displayTitle ?? this.displayTitle,
      state: state ?? this.state,
      questions: questions ?? this.questions,
    );
  }
}

enum MockQuestionnaireDraftState { draft, ready }
