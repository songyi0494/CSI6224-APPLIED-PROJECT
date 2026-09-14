import '../models/clinical_case.dart';

class PatientDecisionPresentation {
  const PatientDecisionPresentation({
    required this.title,
    required this.description,
    required this.messageLabel,
    this.showRecommendation = false,
    this.allowAssessmentEdit = false,
  });

  final String title;
  final String description;
  final String messageLabel;
  final bool showRecommendation;
  final bool allowAssessmentEdit;

  static PatientDecisionPresentation? fromCase(ClinicalCase assessment) {
    switch (assessment.status) {
      case ClinicalCaseStatus.approved:
        return const PatientDecisionPresentation(
          title: 'Recommendation approved',
          description:
              'Your clinician has reviewed your assessment and approved the recommendation.',
          messageLabel: 'Message from your clinician',
          showRecommendation: true,
        );
      case ClinicalCaseStatus.needsMoreInfo:
        return const PatientDecisionPresentation(
          title: 'More information needed',
          description:
              'Your clinician needs some additional information before completing your assessment.',
          messageLabel: 'Message from your clinician',
        );
      case ClinicalCaseStatus.followUpArranged:
        return const PatientDecisionPresentation(
          title: 'Follow-up arranged',
          description:
              'Your clinician has recommended follow-up before the assessment is complete.',
          messageLabel: 'Follow-up details',
        );
      case ClinicalCaseStatus.draft:
      case ClinicalCaseStatus.clinicianInputRequired:
      case ClinicalCaseStatus.awaitingReview:
      case ClinicalCaseStatus.manualReview:
      case ClinicalCaseStatus.withheld:
        return null;
    }
  }
}
