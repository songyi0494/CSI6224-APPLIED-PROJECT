import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/live_pathway.dart';
import '../models/questionnaire.dart';

class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
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
  });
  Future<List<AppUser>> pendingClinicians();
  Future<void> reviewClinician(String id, ClinicianApprovalStatus approval);

  Future<QuestionnaireForm> fetchQuestionnaireForm();
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  });
  Future<LivePathwayResult> evaluatePathway({required String caseId});
  Future<void> savePathwayAnswer({
    required String caseId,
    required String fieldKey,
    required Object value,
  });
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  });

  // BACKEND CONTRACT PENDING: these preserve the existing builder in mock/UI
  // mode only. Songyi's live schema has no questionnaire header or publish
  // state, and custom-question production answer keys remain unresolved.
  Future<List<MockQuestionnaireDraft>> fetchMockQuestionnaireDrafts();
  Future<MockQuestionnaireDraft> saveMockQuestionnaireDraft(
    MockQuestionnaireDraft questionnaire,
  );
  Future<MockQuestionnaireDraft> markMockQuestionnaireDraftReady(String id);
}
