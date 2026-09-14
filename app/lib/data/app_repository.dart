import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway1_clinician_input.dart';
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

  // preserve questionnaire authoring separately from the clinical assessment
  Future<List<Questionnaire>> fetchQuestionnaires();
  Future<Questionnaire> saveQuestionnaire(Questionnaire questionnaire);
  Future<Questionnaire> publishQuestionnaire(String id);
  Future<PatientResponse> submitPatientResponse({
    required String questionnaireId,
    required String patientName,
    required Map<String, Object?> answers,
  });
}
