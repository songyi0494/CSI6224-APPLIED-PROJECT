import 'dart:async';
import 'dart:convert';
import '../utils/new_id.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway_evaluation.dart';
import '../models/questionnaire.dart';
import '../services/clinical_api_client.dart';
import 'app_repository.dart';

class MockAppRepository implements AppRepository {
  MockAppRepository({
    Future<PathwayEvaluation> Function(ClinicalInput)? evaluate,
  }) : _evaluate =
           evaluate ??
           ClinicalApiClient(
             Uri.parse(
               const String.fromEnvironment(
                 'MOCK_ENGINE_URL',
                 defaultValue: 'http://localhost:8787/evaluate',
               ),
             ),
           ).evaluate {
    for (final user in [
      const AppUser(
        id: 'patient-a',
        displayName: 'Avery Martin',
        email: 'patient@example.test',
        role: UserRole.patient,
      ),
      const AppUser(
        id: 'patient-b',
        displayName: 'Jordan Lee',
        email: 'treated@example.test',
        role: UserRole.patient,
      ),
      const AppUser(
        id: 'clinician-a',
        displayName: 'Dr Morgan Chen',
        email: 'clinician@example.test',
        role: UserRole.clinician,
        approvalStatus: ClinicianApprovalStatus.approved,
      ),
      const AppUser(
        id: 'clinician-b',
        displayName: 'Dr Taylor Green',
        email: 'pending@example.test',
        role: UserRole.clinician,
        approvalStatus: ClinicianApprovalStatus.pending,
      ),
      const AppUser(
        id: 'clinician-c',
        displayName: 'Dr Casey Brown',
        email: 'rejected@example.test',
        role: UserRole.clinician,
        approvalStatus: ClinicianApprovalStatus.rejected,
      ),
      const AppUser(
        id: 'admin-a',
        displayName: 'Account administrator',
        email: 'admin@example.test',
        role: UserRole.admin,
      ),
    ]) {
      _users[user.id] = user;
      _passwords[user.id] = 'DemoPass123!';
    }
    _seed('patient-a', false);
    _seed('patient-b', true);
  }
  final Future<PathwayEvaluation> Function(ClinicalInput) _evaluate;
  final _events = StreamController<void>.broadcast();
  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  final Map<String, Map<String, dynamic>> _cases = {};
  final Map<String, String> _assigned = {};
  final List<Questionnaire> _questionnaires = [];
  String? _currentId;
  @override
  bool get isMock => true;
  @override
  Stream<void> get sessionChanges => _events.stream;
  AppUser get _user =>
      _users[_currentId] ?? (throw const AppException('Please sign in again.'));
  void _require(UserRole role) {
    if (_user.role != role ||
        (role == UserRole.clinician && !_user.isClinician))
      throw const AppException('You cannot access this action.');
  }

  void _seed(String patientId, bool treated) {
    final input = ClinicalInput(
      treated: treated,
      age: 71,
      sexAtBirth: 'female',
      postmenopausal: true,
      yearsSinceMenopause: 20,
      minimalTraumaFracture: true,
      fractureSite: 'vertebral',
      egfr: 54,
      frailty: 4,
      lifeExpectancy: 10,
      residentialCare: false,
      poorAdherence: false,
      cognitiveImpairment: false,
      dxaAvailable: true,
      dxaRecent: true,
      tScore: -3.5,
      vitaminD: 65,
      recentMajorFracture: true,
      highRisk: true,
      miOrStroke: false,
    );
    final id = newId();
    _cases[id] = {
      'id': id,
      'patient_id': patientId,
      'patient_name': _users[patientId]!.displayName,
      'revision': 1,
      'status': 'draft',
      'facts': input.toFacts(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<AppUser?> loadProfile() async => _users[_currentId];
  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final matches = _users.values.where(
      (u) => u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (matches.isEmpty || _passwords[matches.first.id] != password)
      throw const AppException('Check your email and password and try again.');
    _currentId = matches.first.id;
    _events.add(null);
    return _user;
  }

  @override
  Future<void> signUp(RegistrationInput input) async {
    if (input.role == UserRole.admin)
      throw const AppException('This account type is not available.');
    if (_users.values.any(
      (u) => u.email.toLowerCase() == input.email.toLowerCase(),
    ))
      throw const AppException('An account already exists for this email.');
    final id = newId();
    _users[id] = AppUser(
      id: id,
      displayName: input.name,
      email: input.email,
      role: input.role,
      dateOfBirth: input.dateOfBirth,
      sexAtBirth: input.sexAtBirth,
      approvalStatus: input.role == UserRole.clinician
          ? ClinicianApprovalStatus.pending
          : null,
    );
    _passwords[id] = input.password;
  }

  @override
  Future<void> signOut() async {
    _currentId = null;
    _events.add(null);
  }

  bool _canRead(Map<String, dynamic> a) =>
      (_user.role == UserRole.patient && a['patient_id'] == _user.id) ||
      (_user.isClinician &&
          a['status'] != 'draft' &&
          (_assigned[a['id']] == null || _assigned[a['id']] == _user.id));
  ClinicalCase _view(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    if (!_user.isClinician) {
      copy.remove('evaluation');
      copy.remove('evaluation_id');
    }
    if (copy['status'] != 'approved') copy.remove('approved_actions');
    return ClinicalCase.fromJson(copy);
  }

  @override
  Future<List<ClinicalCase>> fetchClinicalCases() async =>
      _cases.values.where(_canRead).map(_view).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) async {
    final a = _cases[id];
    if (a == null || !_canRead(a))
      throw const AppException('Assessment not available.');
    return _view(a);
  }

  @override
  Future<ClinicalCase> saveAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  }) async {
    _require(UserRole.patient);
    final old = _cases[id];
    if (old != null) {
      if (old['patient_id'] != _user.id)
        throw const AppException('Assessment not available.');
      if (old['revision'] == revision + 1 &&
          jsonEncode(old['facts']) == jsonEncode(input.toFacts()))
        return _view(old);
      if (old['revision'] != revision ||
          !['draft', 'needs_more_information'].contains(old['status']))
        throw const AppException('Assessment changed. Reload and try again.');
    } else if (revision != 0) {
      throw const AppException('Assessment not available.');
    }
    _cases[id] = {
      'id': id,
      'patient_id': _user.id,
      'patient_name': _user.displayName,
      'revision': revision + 1,
      'facts': input.toFacts(),
      'status': 'draft',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return _view(_cases[id]!);
  }

  @override
  Future<ClinicalCase> submitAssessment({
    required String id,
    required int revision,
    required ClinicalInput input,
  }) async {
    final actor = _user.id;
    final saved = await saveAssessment(
      id: id,
      revision: revision,
      input: input,
    );
    if (_cases[id]!['evaluation'] != null) return _view(_cases[id]!);
    final evaluation = await _evaluate(saved.input);
    if (_user.id != actor || _cases[id]!['revision'] != saved.revision)
      throw const AppException('Assessment changed. Please reload.');
    final a = _cases[id]!;
    if (a['evaluation'] != null) return _view(a);
    a.addAll({
      'status': evaluation.canApprove ? 'awaiting_review' : 'manual_review',
      'pathway': evaluation.pathway,
      'routing_reason': evaluation.routingReason,
      'evaluation_id': newId(),
      'evaluation': _evaluationJson(evaluation),
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return _view(a);
  }

  Map<String, dynamic> _evaluationJson(PathwayEvaluation e) => {
    'pathway': e.pathway,
    'decision': e.decision,
    'rule_version': e.ruleVersion,
    'routing_reason': e.routingReason,
    'actions': e.actions.map((a) => a.raw).toList(),
    'trace': e.trace
        .map(
          (t) => {
            'rule_id': t.ruleId,
            'matched': t.matched,
            'reason': t.reason,
          },
        )
        .toList(),
    'missing_inputs': e.missingInputs,
    'warnings': e.warnings,
  };
  @override
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
  }) async {
    _require(UserRole.clinician);
    final current = await fetchClinicalCase(assessment.id);
    if (!current.canReview ||
        current.revision != assessment.revision ||
        current.updatedAt != assessment.updatedAt ||
        current.evaluationId != assessment.evaluationId)
      throw const AppException('Assessment changed. Reload and try again.');
    if (![
          ClinicalCaseStatus.approved,
          ClinicalCaseStatus.withheld,
          ClinicalCaseStatus.needsMoreInfo,
          ClinicalCaseStatus.followUpArranged,
        ].contains(decision) ||
        notes.trim().isEmpty)
      throw const AppException('Choose a decision and enter notes.');
    if (decision == ClinicalCaseStatus.approved &&
        current.evaluation?.canApprove != true)
      throw const AppException('This assessment needs further review.');
    final a = _cases[assessment.id]!;
    a.addAll({
      'status': decision.value,
      'decision_notes': notes.trim(),
      'reviewed_by': _user.id,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _assigned[assessment.id] = _user.id;
    if (decision == ClinicalCaseStatus.approved)
      a['approved_actions'] = current.evaluation!.actions
          .map((a) => a.raw)
          .toList();
  }

  @override
  Future<List<AppUser>> pendingClinicians() async {
    _require(UserRole.admin);
    return _users.values
        .where(
          (u) =>
              u.role == UserRole.clinician &&
              u.approvalStatus == ClinicianApprovalStatus.pending,
        )
        .toList();
  }

  @override
  Future<void> reviewClinician(
    String id,
    ClinicianApprovalStatus approval,
  ) async {
    _require(UserRole.admin);
    final u = _users[id];
    if (u == null ||
        u.role != UserRole.clinician ||
        u.approvalStatus != ClinicianApprovalStatus.pending ||
        approval == ClinicianApprovalStatus.pending)
      throw const AppException('Account is no longer waiting for approval.');
    _users[id] = u.withApproval(approval);
    _events.add(null);
  }

  @override
  Future<List<Questionnaire>> fetchQuestionnaires() async {
    _require(UserRole.clinician);
    return List.unmodifiable(_questionnaires);
  }

  @override
  Future<Questionnaire> saveQuestionnaire(Questionnaire q) async {
    _require(UserRole.clinician);
    final saved = q.id.isEmpty ? q.copyWith(id: newId()) : q;
    _questionnaires.removeWhere((x) => x.id == saved.id);
    _questionnaires.add(saved);
    return saved;
  }

  @override
  Future<Questionnaire> publishQuestionnaire(String id) async {
    _require(UserRole.clinician);
    return saveQuestionnaire(
      _questionnaires
          .firstWhere((q) => q.id == id)
          .copyWith(status: QuestionnaireStatus.published),
    );
  }

  @override
  Future<PatientResponse> submitPatientResponse({
    required String questionnaireId,
    required String patientName,
    required Map<String, Object?> answers,
  }) async => throw const AppException(
    'Please use the clinical assessment to submit health information.',
  );
}
