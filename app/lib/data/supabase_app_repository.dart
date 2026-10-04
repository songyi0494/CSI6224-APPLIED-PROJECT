import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/clinical_result_contract.dart';
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

String _sanitizedDiagnosticMessage(Object error) {
  var message = error is PostgrestException ? error.message : error.toString();
  message = message.replaceAll(
    RegExp(
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    '<redacted-uuid>',
  );
  message = message.replaceAll(
    RegExp(r'\b[^\s@]+@[^\s@]+\.[^\s@]+\b'),
    '<redacted-email>',
  );
  message = message.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9._-]+\b'),
    '<redacted-token>',
  );
  if (message.length > 500) return '${message.substring(0, 500)}…';
  return message;
}

void _debugRepositoryError(String prefix, Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  final code = error is PostgrestException ? error.code : null;
  debugPrint(
    '$prefix type=${error.runtimeType} code=${code ?? 'n/a'} '
    'message=${_sanitizedDiagnosticMessage(error)}',
  );
  debugPrintStack(stackTrace: stackTrace);
}

class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository(this.client);
  final SupabaseClient client;
  static const clinicalCaseListSelectColumns =
      'id, patient_id, status, submitted_at, updated_at';
  static const clinicalCaseDetailRpc = 'get_clinical_case_detail';
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

  Future<T> _investigationCall<T>(Future<T> Function() work) async {
    try {
      return await work().timeout(const Duration(seconds: 25));
    } on InvestigationConflictException {
      rethrow;
    } on InvestigationServiceUnavailableException {
      rethrow;
    } on AppException {
      rethrow;
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          message.contains('schema cache') ||
          message.contains('function public.get_case_investigations') ||
          message.contains('function public.save_case_investigations')) {
        throw const InvestigationServiceUnavailableException();
      }
      if (message.contains('investigations changed') ||
          message.contains('reload before saving')) {
        throw const InvestigationConflictException();
      }
      if (error.code == '42501' ||
          message.contains('only approved clinicians') ||
          message.contains('assigned in-progress case')) {
        throw const AppException(
          'You are not authorized to access Investigations for this case.',
        );
      }
      throw const AppException(
        'Investigations could not be loaded or saved. Please try again.',
      );
    } on FormatException {
      throw const AppException(
        'The Investigations service returned an invalid response. Pathway start remains unavailable.',
      );
    } catch (_) {
      throw const AppException(
        'Investigations could not be loaded or saved. Please try again.',
      );
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
      final rows = await client.rpc('get_clinician_case_list');
      return (rows as List)
          .map((row) => ClinicalCase.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false);
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
    () => _loadClinicalCaseDetail(id),
    'We could not load this assessment. Please try again.',
  );

  Future<ClinicalCase> _loadClinicalCaseDetail(String id) async {
    try {
      final row = await client.rpc(
        clinicalCaseDetailRpc,
        params: {'p_case_id': id},
      );
      return ClinicalCase.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (error, stackTrace) {
      _debugRepositoryError(
        'CLINICAL CASE DETAIL LOAD ERROR:',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<ClinicalCase> claimClinicalCase(String caseId) => _call(() async {
    await client.rpc('claim_clinical_case', params: {'p_case_id': caseId});
    return _loadClinicalCaseDetail(caseId);
  }, 'This case could not be claimed. Reload the Work Queue and try again.');

  @override
  Future<ClinicalCasePatientSummary> getClinicalCasePatientSummary(
    String caseId,
  ) => _call(() async {
    final result = await client.rpc(
      'get_clinical_case_patient_summary',
      params: {'p_case_id': caseId},
    );
    return ClinicalCasePatientSummary.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }, 'The patient age summary could not be loaded.');

  @override
  Future<CaseInvestigations> getCaseInvestigations(String caseId) =>
      _investigationCall(() async {
        final result = await client.rpc(
          'get_case_investigations',
          params: {'p_case_id': caseId},
        );
        return CaseInvestigations.fromRpcJson(
          Map<String, dynamic>.from(result as Map),
        );
      });

  @override
  Future<CaseInvestigations> saveCaseInvestigations({
    required String caseId,
    required double vitaminDLevel,
    required double ionisedCalcium,
    required double bodyWeightKg,
    required int expectedRevision,
  }) => _investigationCall(() async {
    final result = await client.rpc(
      'save_case_investigations',
      params: {
        'p_case_id': caseId,
        'p_vitamin_d_level': vitaminDLevel,
        'p_ionised_calcium': ionisedCalcium,
        'p_body_weight_kg': bodyWeightKg,
        'p_expected_revision': expectedRevision,
      },
    );
    return CaseInvestigations.fromRpcJson(
      Map<String, dynamic>.from(result as Map),
    );
  });

  Future<ClinicalCase> _caseWithPatientName(Object row) async {
    final json = Map<String, dynamic>.from(row as Map);
    try {
      final profile = await client
          .from('profiles')
          .select('full_name')
          .eq('id', json['patient_id'])
          .maybeSingle();
      json['patient_name'] = profile?['full_name'];
    } catch (error, stackTrace) {
      _debugRepositoryError(
        'CASE PROFILE ENRICHMENT ERROR:',
        error,
        stackTrace,
      );
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
  Future<LivePathwayResult> evaluatePathway({required String caseId}) =>
      _call(() async {
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
      }, 'The pathway could not be evaluated. Reload the case and try again.');

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
    ClinicalResultsReview? resultsReview,
  }) => _call(() async {
    if (decision != ClinicalCaseStatus.approved &&
        decision != ClinicalCaseStatus.withheld) {
      throw const AppException('Choose Approve or Withhold.');
    }
    if (decision == ClinicalCaseStatus.approved && resultsReview == null) {
      throw const AppException(
        'Current Common Advice is required before approving this result.',
      );
    }
    final pathwayRevision = assessment.evaluation?.pathwayRevision;
    final investigationRevision = assessment.evaluation?.investigationRevision;
    if (pathwayRevision == null || investigationRevision == null) {
      throw const AppException(
        'The evaluation revision is unavailable. Reload before deciding.',
      );
    }
    await client.rpc(
      'review_pathway_evaluation',
      params: {
        'p_case_id': assessment.id,
        'p_decision': decision == ClinicalCaseStatus.approved
            ? 'approved'
            : 'withheld',
        'p_clinician_message': notes,
        'p_expected_pathway_revision': pathwayRevision,
        'p_expected_investigation_revision': investigationRevision,
        'p_expected_questionnaire_revision':
            resultsReview?.questionnaireRevision,
      },
    );
  }, 'The final decision could not be saved. No result was released.');

  @override
  Future<ClinicalResultsReview?> getClinicalCaseResultsReview(
    String caseId,
  ) async {
    try {
      final result = await client.rpc(
        'get_clinical_case_results_review',
        params: {'p_case_id': caseId},
      );
      return ClinicalResultsReview.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains(
        'candidate results review is not available',
      )) {
        return null;
      }
      throw const AppException('Common Advice could not be loaded.');
    }
  }

  @override
  Future<ClinicalResultsReview> generateClinicalCaseResultsReview({
    required String caseId,
    required int expectedInvestigationRevision,
    required int expectedQuestionnaireRevision,
  }) => _call(() async {
    final result = await client.rpc(
      'review_clinical_case_results',
      params: {
        'p_case_id': caseId,
        'p_expected_investigation_revision': expectedInvestigationRevision,
        'p_expected_questionnaire_revision': expectedQuestionnaireRevision,
      },
    );
    return ClinicalResultsReview.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }, 'Common Advice could not be generated from the current case data.');

  @override
  Future<List<PatientApprovedResult>> fetchPatientApprovedResults() async {
    try {
      final result = await client.rpc('get_patient_approved_results');
      return (result as List? ?? const [])
          .map(
            (value) => PatientApprovedResult.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        // The pre-release backend has no patient-safe projection. Empty is the
        // only safe compatibility behavior; never fall back to raw case data.
        return const [];
      }
      throw const AppException(
        'Approved assessment results could not be loaded.',
      );
    }
  }

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
          params: {'p_clinician_id': id, 'p_approval': approval.name},
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
    try {
      final row = await client
          .from('questionnaire_responses')
          .select()
          .eq('patient_id', patientId)
          .maybeSingle();
      return row == null ? null : _questionnaireResponse(row);
    } catch (error, stackTrace) {
      _debugRepositoryError(
        'CASE QUESTIONNAIRE LOAD ERROR:',
        error,
        stackTrace,
      );
      rethrow;
    }
  }, 'We could not load the questionnaire response. Please try again.');
  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) => _call(
    () async {
      final patientId = client.auth.currentUser?.id;
      if (patientId == null) throw const AppException('Please sign in again.');
      final profile = await client
          .from('profiles')
          .select('gender')
          .eq('id', patientId)
          .single();
      final profileSex = questionnaireSexFromProfile(
        profile['gender']?.toString(),
      );
      if (profileSex == null) {
        throw const AppException(
          'Sex recorded at birth is unavailable in your profile. Please contact support before submitting.',
        );
      }
      final authoritativeAnswers = <String, Object?>{
        ...answers,
        'sex': profileSex,
      };
      if (profileSex != 'Female') {
        authoritativeAnswers.remove('postmenopausal');
      }
      final productionAnswers = governedQuestionnaireAnswers(
        authoritativeAnswers,
      );
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
      return _questionnaireResponse(
        submitted,
        sessionAnswers: productionAnswers,
      );
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
