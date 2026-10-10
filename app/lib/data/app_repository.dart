import '../models/app_user.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/clinical_result_contract.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/live_pathway.dart';
import '../models/questionnaire.dart';

class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InvestigationConflictException extends AppException {
  const InvestigationConflictException()
    : super(
        'These investigation values were updated elsewhere. Please review the latest values before saving again.',
      );
}

class InvestigationServiceUnavailableException extends AppException {
  const InvestigationServiceUnavailableException()
    : super(
        'The Investigations service is not available in this environment yet. Pathway start is unavailable.',
      );
}

abstract class AppRepository {
  bool get isMock;
  Stream<void> get sessionChanges;
  Future<AppUser?> loadProfile();
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signUp(RegistrationInput input);
  Future<void> signOut();
  Future<List<ClinicalCase>> fetchClinicalCases();
  Future<ClinicalCase> fetchClinicalCase(String id);
  Future<ClinicalCase> claimClinicalCase(String caseId);
  Future<ClinicalCasePatientSummary> getClinicalCasePatientSummary(
    String caseId,
  );
  Future<CaseInvestigations> getCaseInvestigations(String caseId);
  Future<CaseInvestigations> saveCaseInvestigations({
    required String caseId,
    required double vitaminDLevel,
    required double ionisedCalcium,
    required double bodyWeightKg,
    required int expectedRevision,
  });
  Future<ClinicalCase> saveAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  });
  Future<ClinicalCase> submitAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  });
  Future<ClinicalCase> completePathway1ClinicianInput({
    required ClinicalCase assessment,
    required Pathway1ClinicianInput input,
  });
  Future<ClinicalCase> withdrawAssessment({required ClinicalCase assessment});
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
    ClinicalResultsReview? resultsReview,
  });
  Future<ClinicalResultsReview?> getClinicalCaseResultsReview(String caseId);
  Future<ClinicalResultsReview> generateClinicalCaseResultsReview({
    required String caseId,
    required int expectedInvestigationRevision,
    required int expectedQuestionnaireRevision,
  });
  Future<List<PatientApprovedResult>> fetchPatientApprovedResults();
  Future<List<AppUser>> pendingClinicians();
  Future<void> reviewClinician(String id, ClinicianApprovalStatus approval);

  Future<QuestionnaireForm> fetchQuestionnaireForm();
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  });
  Future<bool> hasPatientClinicalCase(String patientId);
  Future<LivePathwayResult> evaluatePathway({required String caseId});
  Future<void> savePathwayAnswer({
    required String caseId,
    required String fieldKey,
    required Object value,
  });
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  });

  Future<QuestionnaireQuestion> createQuestionnaireQuestion({
    required String questionText,
    required QuestionType type,
    required List<String> options,
    required bool isRequired,
  });
  
  Future<QuestionnaireQuestion> updateQuestionnaireQuestion(
    QuestionnaireQuestion question,
  );

  Future<void> deleteQuestionnaireQuestion(String questionId);

  // Mockmode
  Future<List<MockQuestionnaireDraft>> fetchMockQuestionnaireDrafts();
  Future<MockQuestionnaireDraft> saveMockQuestionnaireDraft(
    MockQuestionnaireDraft questionnaire,
  );
  Future<MockQuestionnaireDraft> markMockQuestionnaireDraftReady(String id);
}
