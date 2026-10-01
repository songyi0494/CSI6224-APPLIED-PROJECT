import 'clinical_case.dart';

class ApprovedRecommendation {
  const ApprovedRecommendation({
    required this.id,
    required this.caseId,
    required this.patientName,
    required this.pathway,
    required this.summary,
    required this.clinicianNotes,
    required this.approvedAt,
  });

  final String id;
  final String caseId;
  final String patientName;
  final ClinicalPathway pathway;
  final String summary;
  final String clinicianNotes;
  final DateTime approvedAt;
}
