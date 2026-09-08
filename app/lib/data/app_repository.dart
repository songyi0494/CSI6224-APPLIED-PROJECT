import '../models/app_user.dart';
import '../models/approved_recommendation.dart';
import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';
import '../models/questionnaire.dart';

abstract class AppRepository {
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  });

  Future<List<Questionnaire>> fetchQuestionnaires();

  Future<Questionnaire> saveQuestionnaire(Questionnaire questionnaire);

  Future<Questionnaire> publishQuestionnaire(String questionnaireId);

  Future<List<PatientResponse>> fetchPatientResponses();

  Future<PatientResponse> submitPatientResponse({
    required String questionnaireId,
    required String patientName,
    required Map<String, Object?> answers,
  });

  Future<List<ClinicalCase>> fetchClinicalCases();

  Future<ClinicalCase?> fetchClinicalCase(String caseId);

  Future<List<ApprovedRecommendation>> fetchApprovedRecommendations({
    required String patientName,
  });

  Future<ClinicalCase> saveClinicalCase(ClinicalCase clinicalCase);

  Future<PathwayEvaluation> evaluatePathway(ClinicalCase clinicalCase);

  Future<void> recordClinicianDecision({
    required String caseId,
    required ClinicalCaseStatus decision,
    required String notes,
    String? recommendationSummary,
  });
}
