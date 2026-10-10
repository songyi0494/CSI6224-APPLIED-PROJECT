import '../models/clinical_case.dart';

class PatientDecisionPresentation {
  const PatientDecisionPresentation({
    required this.title,
    required this.description,
    required this.messageLabel,
    this.showRecommendation = false,
    this.allowAssessmentEdit = false,
    this.actionDescription,
    this.nextStepsDescription,
  });

  final String title;
  final String description;
  final String messageLabel;
  final bool showRecommendation;
  final bool allowAssessmentEdit;
  final String? actionDescription;
  final String? nextStepsDescription;

  static PatientDecisionPresentation? fromCase(ClinicalCase assessment) {
    switch (assessment.status) {
      case ClinicalCaseStatus.approved:
        return const PatientDecisionPresentation(
          title: 'Recommendation approved',
          description:
              'Your clinician has reviewed your assessment and approved the recommendation.',
          messageLabel: 'Clinician message',
          showRecommendation: true,
        );
      case ClinicalCaseStatus.needsMoreInfo:
        return const PatientDecisionPresentation(
          title: 'More information needed',
          description:
              'Your clinician needs some additional information before completing your assessment.',
          messageLabel: 'Clinician message',
          actionDescription:
              'Follow the instructions from your clinician so the assessment can be completed.',
        );
      case ClinicalCaseStatus.followUpArranged:
        return const PatientDecisionPresentation(
          title: 'Follow-up arranged',
          description:
              'Your clinician has recommended follow-up before the assessment is complete.',
          messageLabel: 'Clinician message',
          nextStepsDescription:
              'Follow the plan provided by your clinician for the next step.',
        );
      case ClinicalCaseStatus.withheld:
        return const PatientDecisionPresentation(
          title: 'Recommendation withheld',
          description:
              'Your clinician has reviewed the assessment and has not approved the system recommendation.',
          messageLabel: 'Clinician message',
        );
      case ClinicalCaseStatus.draft:
      case ClinicalCaseStatus.clinicianInputRequired:
      case ClinicalCaseStatus.inProgress:
      case ClinicalCaseStatus.evaluated:
      case ClinicalCaseStatus.awaitingReview:
      case ClinicalCaseStatus.manualReview:
      case ClinicalCaseStatus.withdrawn:
        return null;
    }
  }
}
