import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/questionnaire.dart';
import 'app_repository.dart';

class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository(this.client);
  final SupabaseClient client;
  @override
  bool get isMock => false;
  @override
  Stream<void> get sessionChanges => client.auth.onAuthStateChange.map((_) {});
  Future<T> _call<T>(Future<T> Function() work, String message) async {
    try {
      return await work().timeout(const Duration(seconds: 25));
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException(message);
    }
  }

  Map<String, Object?> _patientSubmittedFacts(ClinicalInput input) =>
      {
        for (final entry in input.toFacts().entries)
          if (_patientOwnedFactKeys.contains(entry.key)) entry.key: entry.value,
      };

  static const _patientOwnedFactKeys = {
    'osteoporosisTreatmentStatus',
    'sex',
    'postmenopausal',
    'minimalTraumaFracture',
    'fractureSite',
    'liveInResidentialCare',
  };

  @override
  Future<AppUser?> loadProfile() => _call(() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    // leave a boundary for an MFA challenge without treating aal1 as aal2
    final assurance = client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (assurance.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
        assurance.currentLevel != AuthenticatorAssuranceLevels.aal2) {
      throw const AppException(
        'Additional account verification is required. Contact the administrator.',
      );
    }
    final row = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    if (client.auth.currentUser?.id != user.id) return null;
    return AppUser.fromJson(row);
  }, 'We could not load your account. Try again or sign out.');
  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) => _call(() async {
    await client.auth.signInWithPassword(email: email, password: password);
    try {
      return (await loadProfile())!;
    } catch (_) {
      await client.auth.signOut();
      rethrow;
    }
  }, 'We could not sign you in. Check your email and password and try again.');
  @override
  Future<void> signUp(RegistrationInput input) => _call(() async {
    if (input.role == UserRole.admin)
      throw const AppException(
        'This account type is not available for registration.',
      );
    await client.auth.signUp(
      email: input.email,
      password: input.password,
      data: {
        'full_name': input.name,
        'role': input.role.name,
        if (input.role == UserRole.patient)
          'date_of_birth': input.dateOfBirth
              ?.toIso8601String()
              .split('T')
              .first,
        if (input.role == UserRole.patient) 'sex_at_birth': input.sexAtBirth,
      },
    );
    await client.auth.signOut();
  }, 'We could not create your account. Check your details and try again.');
  @override
  Future<void> signOut() => _call(
    () => client.auth.signOut(),
    'We could not sign you out. Please try again.',
  );
  @override
  Future<List<ClinicalCase>> fetchClinicalCases() => _call(() async {
    final rows = await client.rpc('list_assessments') as List;
    return rows
        .map((r) => ClinicalCase.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }, 'We could not load your assessments. Please try again.');
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) => _call(
    () async => ClinicalCase.fromJson(
      Map<String, dynamic>.from(
        await client.rpc('get_assessment', params: {'p_id': id}) as Map,
      ),
    ),
    'We could not load this assessment. Please try again.',
  );
  @override
  Future<ClinicalCase> saveAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  }) => _call(
    () async => ClinicalCase.fromJson(
      Map<String, dynamic>.from(
        await client.rpc(
              'save_assessment',
              params: {
                'p_id': id,
                'p_expected_revision': revision,
                'p_facts': _patientSubmittedFacts(input),
              },
            )
            as Map,
      ),
    ),
    'Your assessment could not be saved. Reload and try again.',
  );
  @override
  Future<ClinicalCase> submitAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  }) => _call(
    () async {
      final saved = await saveAssessment(
        id: id,
        revision: revision,
        input: input,
      );
      if (input.treated == true) {
        await client.functions.invoke(
          'evaluate_pathway_1',
          body: {'assessment_id': saved.id, 'revision': saved.revision},
        );
      } else {
        await client.rpc(
          'submit_pathway1_for_clinician_input',
          params: {'p_id': saved.id, 'p_revision': saved.revision},
        );
      }
      return fetchClinicalCase(saved.id);
    },
    'Your assessment could not be submitted. Your saved draft can be retried.',
  );
  @override
  Future<ClinicalCase> completePathway1ClinicianInput({
    required ClinicalCase assessment,
    required Pathway1ClinicianInput input,
  }) => _call(
    () async {
      await client.rpc(
        'save_pathway1_clinician_input',
        params: {
          'p_id': assessment.id,
          'p_revision': assessment.revision,
          'p_updated_at': assessment.updatedAt.toUtc().toIso8601String(),
          'p_clinician_facts': input.toJson(),
        },
      );
      await client.functions.invoke(
        'evaluate_pathway_1',
        body: {'assessment_id': assessment.id, 'revision': assessment.revision},
      );
      return fetchClinicalCase(assessment.id);
    },
    'Clinical input could not be saved. Reload and try again.',
  );
  @override
  Future<ClinicalCase> withdrawAssessment({
    required ClinicalCase assessment,
  }) => _call(
    () async => ClinicalCase.fromJson(
      Map<String, dynamic>.from(
        await client.rpc(
              'withdraw_assessment_for_edit',
              params: {
                'p_id': assessment.id,
                'p_revision': assessment.revision,
                'p_updated_at': assessment.updatedAt.toUtc().toIso8601String(),
              },
            )
            as Map,
      ),
    ),
    'This assessment is already being reviewed and can no longer be edited directly. Contact your clinician if information needs to be corrected.',
  );
  @override
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
  }) => _call(() async {
    await client.rpc(
      'record_decision',
      params: {
        'p_id': assessment.id,
        'p_revision': assessment.revision,
        'p_updated_at': assessment.updatedAt.toUtc().toIso8601String(),
        'p_evaluation_id': assessment.evaluationId,
        'p_action': decision.value,
        'p_notes': notes,
      },
    );
  }, 'Your decision could not be saved. Reload the assessment and try again.');
  @override
  Future<List<AppUser>> pendingClinicians() => _call(() async {
    final rows = await client
        .from('profiles')
        .select()
        .eq('role', 'clinician')
        .eq('approval_status', 'pending')
        .order('created_at');
    return rows.map(AppUser.fromJson).toList();
  }, 'We could not load clinician accounts. Please try again.');
  @override
  Future<void> reviewClinician(String id, ClinicianApprovalStatus approval) =>
      _call(() async {
        await client.rpc(
          'review_clinician',
          params: {'p_id': id, 'p_approval': approval.name},
        );
      }, 'The account could not be updated. Refresh and try again.');
  @override
  Future<List<Questionnaire>> fetchQuestionnaires() async =>
      throw const AppException(
        'Questionnaire authoring is not part of this database milestone.',
      );
  @override
  Future<Questionnaire> saveQuestionnaire(Questionnaire q) async =>
      throw const AppException(
        'Questionnaire authoring is not part of this database milestone.',
      );
  @override
  Future<Questionnaire> publishQuestionnaire(String id) async =>
      throw const AppException(
        'Questionnaire authoring is not part of this database milestone.',
      );
  @override
  Future<PatientResponse> submitPatientResponse({
    required String questionnaireId,
    required String patientName,
    required Map<String, Object?> answers,
  }) async => throw const AppException(
    'Please use the clinical assessment to submit health information.',
  );
}
