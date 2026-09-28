import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/live_pathway.dart';
import '../models/patient_questionnaire_catalog.dart';
import '../models/questionnaire.dart';
import 'app_repository.dart';

const profileLoadFailureMessage =
    'Your account profile could not be loaded. Try again or sign out.';
const signInServiceFailureMessage =
    'The sign-in service is unavailable. Check your connection and try again.';

String safeSignInFailureMessage(AuthException error) {
  switch (error.code) {
    case 'invalid_credentials':
    case 'user_not_found':
      return 'Email or password is incorrect.';
    case 'email_not_confirmed':
    case 'insufficient_aal':
    case 'mfa_challenge_expired':
      return 'Additional authentication is required before you can sign in.';
    default:
      return signInServiceFailureMessage;
  }
}

class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository(this.client);
  final SupabaseClient client;
  static const clinicalCaseSelectColumns =
      'id, patient_id, assigned_clinician_id, clinician_facts, pathway, '
      'routing_reason, status, submitted_at, updated_at, '
      'questionnaire_response_id, pathway_revision';
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

  Map<String, Object?> _patientSubmittedFacts(ClinicalInput input) => {
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
        .select('id, role, full_name, date_of_birth, gender, approval_status')
        .eq('id', user.id)
        .single();
    if (client.auth.currentUser?.id != user.id) return null;
    return AppUser.fromJson(row, authenticatedEmail: user.email);
  }, profileLoadFailureMessage);
  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) => _call(() async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw AppException(safeSignInFailureMessage(error));
    }
    try {
      final profile = await loadProfile();
      if (profile == null) {
        throw const AppException(profileLoadFailureMessage);
      }
      return profile;
    } catch (_) {
      try {
        await client.auth.signOut();
      } catch (_) {
        // Preserve the profile-load error even if session cleanup also fails.
      }
      rethrow;
    }
  }, signInServiceFailureMessage);
  @override
  Future<void> signUp(RegistrationInput input) => _call(() async {
    if (input.role == UserRole.admin)
      throw const AppException(
        'This account type is not available for registration.',
      );
    await client.auth.signUp(
      email: input.email,
      password: input.password,
      data: registrationMetadata(input),
    );
    await client.auth.signOut();
  }, 'We could not create your account. Check your details and try again.');

  static Map<String, Object?> registrationMetadata(RegistrationInput input) => {
    'full_name': input.name,
    'role': input.role.name,
    if (input.role == UserRole.patient)
      'date_of_birth': input.dateOfBirth?.toIso8601String().split('T').first,
    if (input.role == UserRole.patient) 'gender': input.sexAtBirth,
  };
  @override
  Future<void> signOut() => _call(
    () => client.auth.signOut(),
    'We could not sign you out. Please try again.',
  );
  @override
  Future<List<ClinicalCase>> fetchClinicalCases() => _call(() async {
    try {
      final rows = await client
          .from('clinical_cases')
          .select(clinicalCaseSelectColumns)
          .order('updated_at', ascending: false);
      return await Future.wait(
        (rows as List).map((r) => _caseWithPatientName(r)),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('CLINICAL CASE LOAD ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }, 'We could not load your assessments. Please try again.');
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) => _call(
    () async => _caseWithPatientName(
      await client
          .from('clinical_cases')
          .select(clinicalCaseSelectColumns)
          .eq('id', id)
          .single(),
    ),
    'We could not load this assessment. Please try again.',
  );

  Future<ClinicalCase> _caseWithPatientName(Object row) async {
    final json = Map<String, dynamic>.from(row as Map);
    try {
      final profile = await client
          .from('profiles')
          .select('full_name')
          .eq('id', json['patient_id'])
          .maybeSingle();
      json['patient_name'] = profile?['full_name'];
    } catch (_) {
      // The case remains usable when profile RLS intentionally hides names.
    }
    return ClinicalCase.fromJson(json);
  }

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
  }) async => throw const AppException(
    'The legacy assessment form is not part of the verified Songyi live workflow. Submit the bone health questionnaire instead.',
  );
  @override
  Future<ClinicalCase> completePathway1ClinicianInput({
    required ClinicalCase assessment,
    required Pathway1ClinicianInput input,
  }) async => throw const AppException(
    'Legacy Pathway 1 batch input is retained for compatibility only. Use the sequential clinical pathway.',
  );

  @override
  Future<LivePathwayResult> evaluatePathway({required String caseId}) => _call(
    () async {
      final caseState = await client
          .from('clinical_cases')
          .select('status')
          .eq('id', caseId)
          .single();
      if (caseState['status'] == 'clinician_input_required') {
        await client.rpc('claim_clinical_case', params: {'p_case_id': caseId});
      }
      final response = await client.functions.invoke(
        'evaluate_pathway',
        body: {'caseId': caseId},
      );
      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        final message = data is Map ? data['error']?.toString() : null;
        throw AppException(
          message ?? 'The pathway service could not evaluate this case.',
        );
      }
      if (response.data is! Map) {
        throw const AppException(
          'The pathway service returned an invalid response.',
        );
      }
      return LivePathwayResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    },
    'The pathway could not be evaluated. Reload the case and try again.',
  );

  @override
  Future<void> savePathwayAnswer({
    required String caseId,
    required String fieldKey,
    required Object value,
  }) => _call(() async {
    final definition = pathwayFactRegistry[fieldKey];
    if (definition == null ||
        (definition.kind == PathwayFactKind.boolean && value is! bool) ||
        (definition.kind == PathwayFactKind.number && value is! num)) {
      throw const AppException('This pathway answer has an unsupported type.');
    }
    await client.rpc(
      'save_pathway_answer',
      params: {'p_case_id': caseId, 'p_field_key': fieldKey, 'p_value': value},
    );
  }, 'The pathway answer could not be saved. Reload the case and try again.');
  @override
  Future<ClinicalCase> withdrawAssessment({
    required ClinicalCase assessment,
  }) async => throw const AppException(
    'Withdrawal is not available until the clinical service can safely return both the questionnaire and its case to draft. Your submitted assessment has not been changed.',
  );
  @override
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
  }) async => throw const AppException(
    'Clinician decision persistence is not available in the verified Songyi live schema. No decision was released to the patient.',
  );
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
  Future<QuestionnaireForm> fetchQuestionnaireForm() => _call(() async {
    final rows = await client
        .from('questionnaire_questions')
        .select()
        .order('display_order');
    final questions = (rows as List)
        .map((row) {
          final json = Map<String, dynamic>.from(row as Map);
          return QuestionnaireQuestion(
            id: json['id'].toString(),
            fieldKey: json['field_key'] as String?,
            questionText: json['question_text'].toString(),
            type: QuestionType.fromDatabaseValue(
              json['question_type'].toString(),
            ),
            options: List<String>.from(json['options'] as List? ?? const []),
            isRequired: json['is_required'] as bool? ?? true,
            displayOrder: (json['display_order'] as num).toInt(),
            createdBy: json['created_by'] as String?,
          );
        })
        .toList(growable: false);
    return buildMaturePatientForm(questions);
  }, 'We could not load the questionnaire. Please try again.');
  @override
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  }) => _call(() async {
    final row = await client
        .from('questionnaire_responses')
        .select()
        .eq('patient_id', patientId)
        .maybeSingle();
    return row == null ? null : _questionnaireResponse(row);
  }, 'We could not load the questionnaire response. Please try again.');
  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) => _call(
    () async {
      final patientId = client.auth.currentUser?.id;
      if (patientId == null) throw const AppException('Please sign in again.');
      final productionAnswers = governedQuestionnaireAnswers(answers);
      var row = await client
          .from('questionnaire_responses')
          .select()
          .eq('patient_id', patientId)
          .maybeSingle();
      if (row == null) {
        row = await client
            .from('questionnaire_responses')
            .insert({
              'patient_id': patientId,
              'answers': productionAnswers,
              'status': 'draft',
            })
            .select()
            .single();
      } else {
        if (row['status'] != 'draft') {
          throw const AppException(
            'This questionnaire has already been submitted.',
          );
        }
        row = await client
            .from('questionnaire_responses')
            .update({'answers': productionAnswers})
            .eq('id', row['id'])
            .eq('status', 'draft')
            .select()
            .single();
      }
      await client.rpc(
        'submit_questionnaire_response',
        params: {'p_response_id': row['id']},
      );
      final submitted = await client
          .from('questionnaire_responses')
          .select()
          .eq('id', row['id'])
          .single();
      return _questionnaireResponse(submitted, sessionAnswers: answers);
    },
    'Your questionnaire could not be submitted. Your answers remain on this screen so you can retry.',
  );

  static Map<String, Object?> governedQuestionnaireAnswers(
    Map<String, Object?> answers,
  ) {
    final unsupported = answers.keys
        .where((key) => !productionQuestionnaireAnswerKeys.contains(key))
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw const AppException(
        'This questionnaire contains an answer that is not approved for production submission. Reload the questionnaire and try again.',
      );
    }
    return Map<String, Object?>.unmodifiable(answers);
  }

  QuestionnaireResponse _questionnaireResponse(
    Map<String, dynamic> row, {
    Map<String, Object?>? sessionAnswers,
  }) => QuestionnaireResponse(
    id: row['id'].toString(),
    patientId: row['patient_id'].toString(),
    status: row['status'] == 'submitted'
        ? QuestionnaireResponseStatus.submitted
        : QuestionnaireResponseStatus.draft,
    revision: (row['revision'] as num?)?.toInt() ?? 0,
    submittedAt: DateTime.tryParse(row['submitted_at']?.toString() ?? ''),
    answers: Map.unmodifiable(
      sessionAnswers ??
          Map<String, Object?>.from(row['answers'] as Map? ?? const {}),
    ),
  );
  @override
  Future<List<MockQuestionnaireDraft>> fetchMockQuestionnaireDrafts() async =>
      throw const AppException(
        'Questionnaire builder persistence is BACKEND CONTRACT PENDING.',
      );
  @override
  Future<MockQuestionnaireDraft> saveMockQuestionnaireDraft(
    MockQuestionnaireDraft questionnaire,
  ) async => throw const AppException(
    'Questionnaire builder persistence is BACKEND CONTRACT PENDING.',
  );
  @override
  Future<MockQuestionnaireDraft> markMockQuestionnaireDraftReady(
    String id,
  ) async => throw const AppException(
    'Questionnaire builder persistence is BACKEND CONTRACT PENDING.',
  );
}
