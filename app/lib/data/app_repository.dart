import '../models/app_user.dart';
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

  Future<List<PatientResponse>> fetchPatientResponses();

  Future<List<ClinicalCase>> fetchClinicalCases();

  Future<ClinicalCase> saveClinicalCase(ClinicalCase clinicalCase);

  Future<PathwayEvaluation> evaluatePathway(ClinicalCase clinicalCase);

  Future<void> recordClinicianDecision({
    required String caseId,
    required ClinicalCaseStatus decision,
    required String notes,
  });
}
