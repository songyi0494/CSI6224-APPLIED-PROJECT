import '../models/clinical_case.dart';
import '../models/questionnaire.dart';

String clinicalPathwayLabel(ClinicalPathway pathway) {
  switch (pathway) {
    case ClinicalPathway.pathway1:
      return 'Pathway 1';
    case ClinicalPathway.pathway2:
      return 'Pathway 2';
  }
}

String clinicalCaseStatusLabel(ClinicalCaseStatus status) => status.label;

String mockQuestionnaireDraftStateLabel(MockQuestionnaireDraftState status) {
  switch (status) {
    case MockQuestionnaireDraftState.draft:
      return 'Draft';
    case MockQuestionnaireDraftState.ready:
      return 'Ready in mock mode';
  }
}

String questionTypeLabel(QuestionType type) {
  switch (type) {
    case QuestionType.text:
      return 'Text';
    case QuestionType.numeric:
      return 'Number';
    case QuestionType.checkbox:
      return 'Checkbox';
    case QuestionType.singleChoice:
      return 'Single choice';
    case QuestionType.multiChoice:
      return 'Multiple choice';
    case QuestionType.dropdown:
      return 'Dropdown';
    case QuestionType.scale:
      return 'Scale';
  }
}

String pathwayDecisionLabel(String decision) {
  switch (decision) {
    case 'action_taken':
      return 'Action available';
    case 'needs_more_information':
      return 'Needs more information';
    case 'requires_rule_engine':
      return 'Rule engine required';
    case 'not_applicable':
      return 'Not applicable';
    default:
      return decision
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
  }
}

String pathwayActionTypeLabel(String type) {
  switch (type) {
    case 'pathwayRedirect':
      return 'Pathway redirect';
    case 'integrationGap':
      return 'Pending backend rule';
    case 'treatmentOptions':
      return 'Treatment options';
    case 'followUp':
      return 'Follow-up';
    case 'referral':
      return 'Referral';
    case 'medication':
      return 'Medication option';
    case 'review':
      return 'Review';
    case 'investigation':
      return 'Investigation';
    case 'consideration':
      return 'Clinical consideration';
    default:
      return type
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (match) => '${match.group(1)} ${match.group(2)}',
          )
          .split(RegExp(r'[_\s]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
  }
}
