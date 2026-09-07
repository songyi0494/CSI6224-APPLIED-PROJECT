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
    required this.patientName,
    required this.questionnaireTitle,
    required this.submittedAt,
    required this.answers,
  });

  final String id;
  final String patientName;
  final String questionnaireTitle;
  final DateTime submittedAt;
  final Map<String, Object?> answers;
}
