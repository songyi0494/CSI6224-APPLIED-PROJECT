class Questionnaire {
  const Questionnaire({
    required this.id,
    required this.title,
    required this.status,
    required this.questions,
  });

  final String id;
  final String title;
  final QuestionnaireStatus status;
  final List<QuestionDefinition> questions;

  Questionnaire copyWith({
    String? id,
    String? title,
    QuestionnaireStatus? status,
    List<QuestionDefinition>? questions,
  }) {
    return Questionnaire(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      questions: questions ?? this.questions,
    );
  }
}

enum QuestionnaireStatus { draft, published, closed }

enum QuestionType { text, yesNo, number, scale, choice }

class QuestionDefinition {
  const QuestionDefinition({
    required this.id,
    required this.prompt,
    required this.type,
    this.required = true,
    this.options = const [],
  });

  final String id;
  final String prompt;
  final QuestionType type;
  final bool required;
  final List<String> options;

  QuestionDefinition copyWith({
    String? id,
    String? prompt,
    QuestionType? type,
    bool? required,
    List<String>? options,
  }) {
    return QuestionDefinition(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      type: type ?? this.type,
      required: required ?? this.required,
      options: options ?? this.options,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'type': type.name,
        'required': required,
        'options': options,
      };
}

class PatientResponse {
  const PatientResponse({
    required this.id,
    required this.questionnaireId,
    required this.patientName,
    required this.questionnaireTitle,
    required this.submittedAt,
    required this.answers,
  });

  final String id;
  final String questionnaireId;
  final String patientName;
  final String questionnaireTitle;
  final DateTime submittedAt;
  final Map<String, Object?> answers;
}
