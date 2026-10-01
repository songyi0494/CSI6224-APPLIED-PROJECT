import 'pathway_evaluation.dart';

class ClinicalCasePatientSummary {
  const ClinicalCasePatientSummary({
    required this.caseId,
    required this.patientDisplayName,
    required this.age,
    required this.ageAsOf,
  });

  final String caseId;
  final String patientDisplayName;
  final int? age;
  final DateTime ageAsOf;

  factory ClinicalCasePatientSummary.fromJson(Map<String, dynamic> json) {
    return ClinicalCasePatientSummary(
      caseId: json['caseId'].toString(),
      patientDisplayName: json['patientDisplayName']?.toString() ?? 'Patient',
      age: (json['age'] as num?)?.toInt(),
      ageAsOf: DateTime.parse(json['ageAsOf'].toString()),
    );
  }
}

class ClinicalResultsReview {
  const ClinicalResultsReview({
    required this.commonAdvice,
    required this.investigationRevision,
    required this.questionnaireRevision,
    required this.generatedAt,
  });

  final List<String> commonAdvice;
  final int investigationRevision;
  final int questionnaireRevision;
  final DateTime generatedAt;

  factory ClinicalResultsReview.fromJson(Map<String, dynamic> json) {
    final source = Map<String, dynamic>.from(
      json['source'] as Map? ?? const {},
    );
    final advice = <String>[];

    void addRecommendation(String key) {
      final section = Map<String, dynamic>.from(json[key] as Map? ?? const {});
      final value = section['recommendation']?.toString().trim();
      if (value != null && value.isNotEmpty) advice.add(value);
    }

    addRecommendation('vitaminD');
    addRecommendation('calcium');
    addRecommendation('protein');
    advice.addAll(
      (json['lifestyleAdvice'] as List? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty),
    );

    return ClinicalResultsReview(
      commonAdvice: List.unmodifiable(advice),
      investigationRevision:
          (source['investigationRevision'] as num?)?.toInt() ?? 0,
      questionnaireRevision:
          (source['questionnaireRevision'] as num?)?.toInt() ?? 0,
      generatedAt:
          DateTime.tryParse(source['generatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class PatientApprovedResult {
  const PatientApprovedResult({
    required this.caseId,
    required this.reviewedAt,
    required this.lifestyleRecommendations,
    required this.careRecommendations,
    required this.clinicianMessage,
  });

  final String caseId;
  final DateTime reviewedAt;
  final List<String> lifestyleRecommendations;
  final List<PathwayAction> careRecommendations;
  final String clinicianMessage;

  factory PatientApprovedResult.fromJson(Map<String, dynamic> json) {
    return PatientApprovedResult(
      caseId: json['caseId'].toString(),
      reviewedAt: DateTime.parse(json['reviewedAt'].toString()),
      lifestyleRecommendations: List<String>.from(
        json['lifestyleRecommendations'] as List? ?? const [],
      ),
      careRecommendations: (json['careRecommendation'] as List? ?? const [])
          .map(
            (value) =>
                PathwayAction.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      clinicianMessage: json['clinicianMessage']?.toString() ?? '',
    );
  }
}
