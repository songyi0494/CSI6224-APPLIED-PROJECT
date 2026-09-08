class ClinicalCase {
  const ClinicalCase({
    required this.id,
    required this.patientName,
    required this.pathway,
    required this.facts,
    required this.status,
  });

  final String id;
  final String patientName;
  final ClinicalPathway pathway;
  final Map<String, Object?> facts;
  final ClinicalCaseStatus status;

  ClinicalCase copyWith({
    String? id,
    String? patientName,
    ClinicalPathway? pathway,
    Map<String, Object?>? facts,
    ClinicalCaseStatus? status,
  }) {
    return ClinicalCase(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      pathway: pathway ?? this.pathway,
      facts: facts ?? this.facts,
      status: status ?? this.status,
    );
  }
}

enum ClinicalPathway { pathway1, pathway2 }

enum ClinicalCaseStatus {
  draft,
  evaluated,
  approved,
  withheld,
  needsMoreInfo,
  followUpArranged,
}
