import 'dart:async';
import 'dart:convert';
import '../utils/new_id.dart';
import '../models/app_user.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/clinical_result_contract.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/pathway_evaluation.dart';
import '../models/live_pathway.dart';
import '../models/patient_questionnaire_catalog.dart';
import '../models/questionnaire.dart';
import 'app_repository.dart';

class MockAppRepository implements AppRepository {
  MockAppRepository({
    Future<PathwayEvaluation> Function(ClinicalInput)? evaluate,
  }) : _evaluate = evaluate ?? _evaluateLocally {
    for (final user in [
      AppUser(
        id: 'patient-a',
        displayName: 'Avery Martin',
        email: 'patient@example.test',
        role: UserRole.patient,
        dateOfBirth: DateTime(1955, 1, 1),
        sexAtBirth: 'female',
      ),
      AppUser(
        id: 'patient-b',
        displayName: 'Jordan Lee',
        email: 'treated@example.test',
        role: UserRole.patient,
        dateOfBirth: DateTime(1955, 1, 1),
        sexAtBirth: 'female',
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
  final Map<String, CaseInvestigations> _investigations = {};
  final Map<String, ClinicalResultsReview> _resultsReviews = {};
  final List<MockQuestionnaireDraft> _questionnaireDrafts = [];
  final Map<String, QuestionnaireResponse> _questionnaireResponses = {};
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
    final patient = _users[patientId]!;
    final input = ClinicalInput(
      treated: treated,
      age: _ageFromDateOfBirth(patient.dateOfBirth),
      sexAtBirth: patient.sexAtBirth,
      postmenopausal: true,
      yearsSinceMenopause: 20,
      minimalTraumaFracture: true,
      fractureSite: 'vertebral',
      egfr: true,
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

  int? _ageFromDateOfBirth(DateTime? birth) {
    if (birth == null) return null;
    final now = DateTime.now();
    return now.year -
        birth.year -
        ((now.month < birth.month ||
                (now.month == birth.month && now.day < birth.day))
            ? 1
            : 0);
  }

  Map<String, Object?> _patientSubmittedFacts(ClinicalInput input) {
    final facts = {
      for (final entry in input.toFacts().entries)
        if (_patientOwnedFactKeys.contains(entry.key)) entry.key: entry.value,
    };
    facts['age'] = _ageFromDateOfBirth(_user.dateOfBirth);
    return facts;
  }

  static const _patientOwnedFactKeys = {
    'osteoporosisTreatmentStatus',
    'sex',
    'postmenopausal',
    'minimalTraumaFracture',
    'fractureSite',
    'liveInResidentialCare',
  };

  static const _activeAssessmentStatuses = {
    'draft',
    'clinician_input_required',
    'awaiting_review',
    'manual_review',
    'needs_more_information',
  };

  static const _clinicianOwnedMissingInputs = {
    'eGFR',
    'clinicalFrailtyScore',
    'lifeExpectancy',
    'knownPoorMedicationAdherence',
    'cognitiveImpairment',
    'testAvailable',
    'testWithinLast2Years',
    'T-score',
    'hipVertebralOrMultipleFracturesInLast24M',
    'highRisk',
    'yearSincePostmenopausal',
    'isRobustWoman',
  };

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
    copy['profile_sex_at_birth'] = _users[copy['patient_id']]?.sexAtBirth;
    if (!_user.isClinician) {
      copy.remove('evaluation');
      copy.remove('evaluation_id');
      copy.remove('clinician_facts');
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
  Future<ClinicalCase> claimClinicalCase(String caseId) async {
    _require(UserRole.clinician);
    final row = _cases[caseId];
    if (row == null || !_canRead(row)) {
      throw const AppException('Assessment not available.');
    }
    final assigned = _assigned[caseId];
    if (row['status'] == 'in_progress' && assigned == _user.id) {
      return _view(row);
    }
    if (row['status'] != 'clinician_input_required' || assigned != null) {
      throw const AppException('This case is not available to claim.');
    }
    row['status'] = 'in_progress';
    row['assigned_clinician_id'] = _user.id;
    row['claimed_at'] = DateTime.now().toUtc().toIso8601String();
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();
    _assigned[caseId] = _user.id;
    return _view(row);
  }

  @override
  Future<ClinicalCasePatientSummary> getClinicalCasePatientSummary(
    String caseId,
  ) async {
    _require(UserRole.clinician);
    final row = _cases[caseId];
    if (row == null || !_canRead(row)) {
      throw const AppException('Assessment not available.');
    }
    final patient = _users[row['patient_id']];
    return ClinicalCasePatientSummary(
      caseId: caseId,
      patientDisplayName: patient?.displayName ?? 'Patient',
      age: _ageFromDateOfBirth(patient?.dateOfBirth),
      ageAsOf: DateTime.now(),
    );
  }

  void _requireAssignedCase(String caseId, {required bool inProgress}) {
    _require(UserRole.clinician);
    final row = _cases[caseId];
    if (row == null ||
        _assigned[caseId] != _user.id ||
        (inProgress && row['status'] != 'in_progress')) {
      throw const AppException(
        'Investigations are available only for your assigned case.',
      );
    }
  }

  @override
  Future<CaseInvestigations> getCaseInvestigations(String caseId) async {
    _requireAssignedCase(caseId, inProgress: false);
    return _investigations[caseId] ?? CaseInvestigations.empty(caseId);
  }

  @override
  Future<CaseInvestigations> saveCaseInvestigations({
    required String caseId,
    required double vitaminDLevel,
    required double ionisedCalcium,
    required double bodyWeightKg,
    required int expectedRevision,
  }) async {
    _requireAssignedCase(caseId, inProgress: true);
    if (!vitaminDLevel.isFinite || vitaminDLevel < 0) {
      throw const AppException(
        'Vitamin D must be a finite non-negative value in nmol/L.',
      );
    }
    if (!ionisedCalcium.isFinite || ionisedCalcium < 0) {
      throw const AppException(
        'Ionised calcium must be a finite non-negative value in mmol/L.',
      );
    }
    if (!bodyWeightKg.isFinite || bodyWeightKg <= 0) {
      throw const AppException(
        'Body weight must be a finite positive value in kg.',
      );
    }
    final current = _investigations[caseId] ?? CaseInvestigations.empty(caseId);
    if (current.revision != expectedRevision) {
      throw const InvestigationConflictException();
    }
    final now = DateTime.now().toUtc();
    final saved = CaseInvestigations(
      caseId: caseId,
      vitaminDLevel: vitaminDLevel,
      ionisedCalcium: ionisedCalcium,
      bodyWeightKg: bodyWeightKg,
      revision: current.revision + 1,
      isComplete: true,
      completedAt: now,
      updatedAt: now,
    );
    _investigations[caseId] = saved;
    return saved;
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
          jsonEncode(old['facts']) == jsonEncode(_patientSubmittedFacts(input)))
        return _view(old);
      if (old['revision'] != revision || old['status'] != 'draft')
        throw const AppException('Assessment changed. Reload and try again.');
    } else if (revision != 0) {
      throw const AppException('Assessment not available.');
    } else if (_cases.values.any(
      (assessment) =>
          assessment['patient_id'] == _user.id &&
          _activeAssessmentStatuses.contains(assessment['status']),
    )) {
      throw const AppException('You already have an assessment in progress.');
    }
    _cases[id] = {
      'id': id,
      'patient_id': _user.id,
      'patient_name': _user.displayName,
      'revision': revision + 1,
      'facts': _patientSubmittedFacts(input),
      if (old?['clinician_facts'] != null)
        'clinician_facts': old!['clinician_facts'],
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
    final existing = _cases[id];
    if (existing != null &&
        existing['patient_id'] == _user.id &&
        existing['status'] == 'clinician_input_required' &&
        existing['revision'] == revision + 1 &&
        jsonEncode(existing['facts']) ==
            jsonEncode(_patientSubmittedFacts(input))) {
      return _view(existing);
    }
    final saved = await saveAssessment(
      id: id,
      revision: revision,
      input: input,
    );
    if (saved.input.treated == true) {
      return _completeEvaluation(id, saved, actor);
    }
    final a = _cases[id]!;
    a.addAll({
      'status': 'clinician_input_required',
      'pathway': 'PATHWAY1',
      'routing_reason':
          'No previous or current osteoporosis treatment was recorded.',
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return _view(a);
  }

  @override
  Future<ClinicalCase> withdrawAssessment({
    required ClinicalCase assessment,
  }) async {
    _require(UserRole.patient);
    final a = _cases[assessment.id];
    if (a == null || a['patient_id'] != _user.id) {
      throw const AppException('Assessment not available.');
    }
    final updatedAt = DateTime.parse(a['updated_at'] as String);
    final clinicianFacts = a['clinician_facts'];
    final hasClinicianFacts =
        clinicianFacts is Map && clinicianFacts.isNotEmpty;
    final hasEvaluation = a['evaluation'] != null || a['evaluation_id'] != null;
    final hasDecision =
        a['decision_notes'] != null ||
        a['reviewed_by'] != null ||
        a['reviewed_at'] != null;
    if (a['revision'] != assessment.revision ||
        !updatedAt.isAtSameMomentAs(assessment.updatedAt)) {
      throw const AppException('Assessment changed. Reload and try again.');
    }
    if (a['status'] != 'clinician_input_required' ||
        hasClinicianFacts ||
        hasEvaluation ||
        hasDecision) {
      throw const AppException(
        'This assessment is already being reviewed and can no longer be edited directly. Contact your clinician if information needs to be corrected.',
      );
    }
    a.addAll({
      'status': 'draft',
      'pathway': null,
      'routing_reason': null,
      'submitted_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return _view(a);
  }

  Future<ClinicalCase> _completeEvaluation(
    String id,
    ClinicalCase saved,
    String actor,
  ) async {
    if (_cases[id]!['evaluation'] != null &&
        _cases[id]!['status'] != 'clinician_input_required') {
      return _view(_cases[id]!);
    }
    final evaluation = await _evaluate(saved.input);
    if (_user.id != actor || _cases[id]!['revision'] != saved.revision)
      throw const AppException('Assessment changed. Please reload.');
    final a = _cases[id]!;
    if (a['evaluation'] != null && a['status'] != 'clinician_input_required') {
      return _view(a);
    }
    a.addAll({
      'status': _statusAfterEvaluation(evaluation),
      'pathway': evaluation.pathway,
      'routing_reason': evaluation.routingReason,
      'evaluation_id': newId(),
      'evaluation': _evaluationJson(evaluation),
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return _view(a);
  }

  String _statusAfterEvaluation(PathwayEvaluation evaluation) {
    if (evaluation.canApprove) return 'awaiting_review';
    if (evaluation.decision == 'needs_more_information' &&
        evaluation.missingInputs.isNotEmpty &&
        evaluation.missingInputs.every(_clinicianOwnedMissingInputs.contains)) {
      return 'clinician_input_required';
    }
    return 'manual_review';
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
            'input': t.input,
            'reason': t.reason,
          },
        )
        .toList(),
    'missing_inputs': e.missingInputs,
    'warnings': e.warnings,
  };

  @override
  Future<ClinicalCase> completePathway1ClinicianInput({
    required ClinicalCase assessment,
    required Pathway1ClinicianInput input,
  }) async {
    _require(UserRole.clinician);
    final current = await fetchClinicalCase(assessment.id);
    if (!current.needsClinicianInput ||
        current.revision != assessment.revision ||
        current.updatedAt != assessment.updatedAt) {
      throw const AppException('Assessment changed. Reload and try again.');
    }
    if (current.pathway != ClinicalPathway.pathway1) {
      throw const AppException('Pathway 1 clinical input is not available.');
    }
    final a = _cases[assessment.id]!;
    final patientFacts = Map<String, Object?>.from(a['facts'] as Map);
    final clinicianFacts = input.toJson();
    final evaluationFacts = {...patientFacts, ...input.toEvaluatorFacts()};
    final evaluation = await _evaluate(
      ClinicalInput.fromFacts(evaluationFacts),
    );
    a.addAll({
      'clinician_facts': clinicianFacts,
      'status': _statusAfterEvaluation(evaluation),
      'pathway': evaluation.pathway,
      'routing_reason': evaluation.routingReason,
      'evaluation_id': newId(),
      'evaluation': _evaluationJson(evaluation),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _assigned[assessment.id] = _user.id;
    return _view(a);
  }

  @override
  Future<void> savePathwayAnswer({
    required String caseId,
    required String fieldKey,
    required Object value,
  }) async {
    _require(UserRole.clinician);
    final definition = pathwayFactRegistry[fieldKey];
    if (definition == null || !definition.accepts(value)) {
      throw const AppException('This pathway answer has an unsupported type.');
    }
    final row = _cases[caseId];
    if (row == null || row['status'] != 'in_progress') {
      throw const AppException(
        'Pathway answers can only be changed while the case is in progress.',
      );
    }
    final investigations = _investigations[caseId];
    if (investigations == null || !investigations.canStartPathway) {
      throw const AppException(
        'Complete and confirm Investigations before starting the pathway.',
      );
    }
    row['clinician_facts'] = Map<String, Object?>.from(
      row['clinician_facts'] as Map? ?? const {},
    )..[fieldKey] = value;
    row['pathway_revision'] = (row['pathway_revision'] as int? ?? 0) + 1;
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<LivePathwayResult> evaluatePathway({required String caseId}) async {
    _require(UserRole.clinician);
    final row = _cases[caseId];
    if (row == null) throw const AppException('Assessment not available.');
    if (row['status'] == 'evaluated') {
      return LivePathwayResult.fromJson(
        Map<String, dynamic>.from(row['rule_evaluation'] as Map),
      );
    }
    if (row['status'] != 'in_progress' || _assigned[caseId] != _user.id) {
      throw const AppException(
        'This case is not available for pathway evaluation.',
      );
    }
    final investigations = _investigations[caseId];
    if (investigations == null || !investigations.canStartPathway) {
      throw const AppException(
        'Complete and confirm Investigations before starting the pathway.',
      );
    }
    final result = _mockLiveEvaluate(
      Map<String, Object?>.from(row['clinician_facts'] as Map? ?? const {}),
      patient: _users[row['patient_id']],
      menopause: _questionnaireResponses.containsKey(row['patient_id'])
          ? _questionnaireResponses[row['patient_id']]!
                .answers['postmenopausal']
          : (row['facts'] as Map?)?['postmenopausal'],
    );
    row['pathway'] = result.pathwayId;
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (result is CompletedPathwayEvaluation) {
      final json = _liveResultJson(result);
      row['status'] = 'evaluated';
      row['rule_evaluation'] = json;
      row['evaluation'] = json;
      row['evaluation_id'] = newId();
    }
    return result;
  }

  LivePathwayResult _mockLiveEvaluate(
    Map<String, Object?> facts, {
    required AppUser? patient,
    required Object? menopause,
  }) {
    final trace = <LivePathwayTraceEntry>[];
    PathwayQuestionStep ask(
      String pathway,
      String node,
      String prompt,
      List<String> facts,
    ) => PathwayQuestionStep(
      pathwayId: pathway,
      nodeId: node,
      question: prompt,
      requiredFacts: facts,
      trace: List.unmodifiable(trace),
    );
    void visit(String pathway, String node, bool matched, String next) =>
        trace.add(
          LivePathwayTraceEntry(
            nodeId: node,
            pathwayId: pathway,
            nodeType: 'decision',
            matched: matched,
            nextNodeId: next,
          ),
        );
    CompletedPathwayEvaluation finish(String pathway, String action) {
      trace.add(
        LivePathwayTraceEntry(
          nodeId: 'RESULT_${trace.length + 1}',
          pathwayId: pathway,
          nodeType: 'result',
          actionsTriggered: [action],
        ),
      );
      return CompletedPathwayEvaluation(
        pathwayId: pathway,
        actions: [
          {'type': 'recommendation', 'recommendation': action},
        ],
        trace: List.unmodifiable(trace),
      );
    }

    bool anyMissing(List<String> keys) =>
        keys.any((key) => !facts.containsKey(key));

    final sex = patient?.sexAtBirth;
    final age = _ageFromDateOfBirth(patient?.dateOfBirth);
    final menopausal = menopause == true || menopause == 'Yes'
        ? true
        : menopause == false || menopause == 'No'
        ? false
        : null;
    final demographic = sex == 'female'
        ? menopausal
        : sex == 'male'
        ? (age == null ? null : age > 50)
        : sex == null
        ? null
        : false;
    if (demographic == null) {
      return const PathwayRuntimeError(
        pathwayId: 'PATHWAY1',
        trace: [],
        message:
            'More information is required before the recommendation can be completed. Check the patient profile or submitted questionnaire.',
      );
    }
    visit(
      'PATHWAY1',
      'P1_DEMOGRAPHIC_ELIGIBILITY',
      demographic,
      demographic ? 'MINIMAL_TRAUMA_KNOWN' : 'P1_ELIGIBILITY_NOT_MET',
    );
    if (!demographic) {
      return PathwayRuntimeError(
        pathwayId: 'PATHWAY1',
        trace: trace,
        message:
            'The patient does not meet the P1 entry criteria. Clinician review is required before choosing another pathway.',
      );
    }
    for (final key in ['minimalTraumaFracture', 'fractureSite']) {
      if (!pathwayFactRegistry[key]!.accepts(facts[key])) {
        return ask(
          'PATHWAY1',
          key == 'minimalTraumaFracture'
              ? 'MINIMAL_TRAUMA_KNOWN'
              : 'FRACTURE_SITE_KNOWN',
          key == 'minimalTraumaFracture'
              ? 'Did the fracture occur after a fall from standing height or less?'
              : 'Where was the fracture?',
          [key],
        );
      }
      if (facts[key] == 'not_sure') {
        return PathwayRuntimeError(
          pathwayId: 'PATHWAY1',
          trace: trace,
          message:
              'More information is required before the recommendation can be completed. Confirm the fracture mechanism and site.',
        );
      }
      if ((key == 'minimalTraumaFracture' && facts[key] == 'no') ||
          (key == 'fractureSite' &&
              ['hand', 'foot', 'face', 'ankle'].contains(facts[key]))) {
        return PathwayRuntimeError(
          pathwayId: 'PATHWAY1',
          trace: trace,
          message:
              'The patient does not meet the P1 entry criteria. Clinician review is required before choosing another pathway.',
        );
      }
      visit(
        'PATHWAY1',
        key == 'minimalTraumaFracture'
            ? 'MINIMAL_TRAUMA_FRACTURE'
            : 'FRACTURE_SITE_ELIGIBLE',
        true,
        key == 'minimalTraumaFracture'
            ? 'FRACTURE_SITE_KNOWN'
            : 'RENAL_DYSFUNCTION',
      );
    }
    if (facts['eGFR'] is! bool) {
      return ask(
        'PATHWAY1',
        'RENAL_DYSFUNCTION',
        "Is the patient's eGFR 30 mL/min or higher?",
        const ['eGFR'],
      );
    }
    final renalOk = facts['eGFR'] as bool;
    visit(
      'PATHWAY1',
      'RENAL_DYSFUNCTION',
      renalOk,
      renalOk ? 'ON_OSTEOPOROSIS_TREATMENT' : 'RESULT_RENAL_REVIEW',
    );
    if (!renalOk) {
      return finish(
        'PATHWAY1',
        'Refer for specialist review of renal function and treatment options.',
      );
    }
    if (!facts.containsKey('osteoporosisTreatmentStatus')) {
      return ask(
        'PATHWAY1',
        'ON_OSTEOPOROSIS_TREATMENT',
        'Is the patient currently on osteoporosis treatment?',
        const ['osteoporosisTreatmentStatus'],
      );
    }
    final treated = facts['osteoporosisTreatmentStatus'] as bool;
    visit(
      'PATHWAY1',
      'ON_OSTEOPOROSIS_TREATMENT',
      treated,
      treated ? 'ON_ANTIRESORPTIVE_TREATMENT' : 'RESIDENTIAL_OR_FRAILTY',
    );
    if (treated) return _mockPathway2(facts, trace);

    const residential = [
      'liveInResidentialCare',
      'clinicalFrailtyScore',
      'lifeExpectancy',
    ];
    if (anyMissing(residential)) {
      return ask(
        'PATHWAY1',
        'RESIDENTIAL_OR_FRAILTY',
        'Does the patient live in residential care, have severe frality, or have a life expectancy of 7 years or less?',
        residential,
      );
    }
    final vulnerable =
        facts['liveInResidentialCare'] == true ||
        (facts['clinicalFrailtyScore'] as num) >= 7 ||
        (facts['lifeExpectancy'] as num) < 7;
    visit(
      'PATHWAY1',
      'RESIDENTIAL_OR_FRAILTY',
      vulnerable,
      vulnerable ? 'RESULT_INDIVIDUAL_REVIEW' : 'ADHERENCE_CONCERN',
    );
    if (vulnerable) {
      return finish(
        'PATHWAY1',
        'Use individualised clinical review and shared decision-making.',
      );
    }
    const adherence = ['knownPoorMedicationAdherence', 'cognitiveImpairment'];
    if (anyMissing(adherence)) {
      return ask(
        'PATHWAY1',
        'ADHERENCE_CONCERN',
        'Is the patient able to adhere to their treatment plan? (Please answer the following questions.)',
        adherence,
      );
    }
    final concern =
        facts['knownPoorMedicationAdherence'] == true ||
        facts['cognitiveImpairment'] == true;
    visit(
      'PATHWAY1',
      'ADHERENCE_CONCERN',
      concern,
      concern ? 'RESULT_ADHERENCE_SUPPORT' : 'DXA_SCAN_AVAILABILITY',
    );
    if (concern) {
      return finish(
        'PATHWAY1',
        'Address adherence barriers and provide an appropriate supported plan.',
      );
    }
    if (!facts.containsKey('testAvailability')) {
      return ask(
        'PATHWAY1',
        'DXA_SCAN_AVAILABILITY',
        'Can the patient undergo a BMD DXA scan? (Select Yes if the patient has had a scan within prior 2 years)',
        const ['testAvailability'],
      );
    }
    final testAvailable = facts['testAvailability'] as bool;
    visit(
      'PATHWAY1',
      'DXA_SCAN_AVAILABILITY',
      testAvailable,
      testAvailable ? 'T_SCORE_CHECK' : 'RESULT_NO_DXA',
    );
    if (!testAvailable) {
      return finish(
        'PATHWAY1',
        'Use clinical risk assessment when DXA is not available.',
      );
    }
    const tScores = ['femoralNeckTscore', 'hipTscore', 'lumbarSpineTscore'];
    if (anyMissing(tScores)) {
      return ask(
        'PATHWAY1',
        'T_SCORE_CHECK',
        "What are the patient's T-score for the femoral neck, hip, and lumbar spine?",
        tScores,
      );
    }
    final low = tScores.any((key) => (facts[key] as num) <= -2.5);
    visit(
      'PATHWAY1',
      'T_SCORE_CHECK',
      low,
      low ? 'RECENT_MAJOR_FRACTURES' : 'RESULT_MONITOR',
    );
    if (!low) {
      return finish(
        'PATHWAY1',
        'Continue risk-factor management and monitoring.',
      );
    }
    if (!facts.containsKey('hipVertebralOrMultipleFracturesInLast24M')) {
      return ask(
        'PATHWAY1',
        'RECENT_MAJOR_FRACTURES',
        'Has the patient had a hip fracture, vertebral fracture, or fractures at 2 or more sites in last 24 months?',
        const ['hipVertebralOrMultipleFracturesInLast24M'],
      );
    }
    final recent = facts['hipVertebralOrMultipleFracturesInLast24M'] as bool;
    visit(
      'PATHWAY1',
      'RECENT_MAJOR_FRACTURES',
      recent,
      recent ? 'RESULT_VERY_HIGH_RISK' : 'HIGH_RISK_CHECK',
    );
    if (recent) {
      return finish(
        'PATHWAY1',
        'Refer for very-high-risk osteoporosis treatment review.',
      );
    }
    const highRisk = [
      'femoralNeckTscore',
      'hipTscore',
      'lumbarSpineTscore',
      'recentFractureWithin2Y',
      'historyOf2orMoreFractures',
      'clinicalRiskFactors',
      'FRAX10YmajorOsteoporoticFractureRiskPercent',
      'FRAX10YmajorHipFractureRiskPercent',
    ];
    if (anyMissing(highRisk)) {
      return ask(
        'PATHWAY1',
        'HIGH_RISK_CHECK',
        'Is the patient at very high risk? (Please answer the following questions.)',
        highRisk,
      );
    }
    return finish(
      'PATHWAY1',
      'Review osteoporosis treatment options with the patient.',
    );
  }

  LivePathwayResult _mockPathway2(
    Map<String, Object?> facts,
    List<LivePathwayTraceEntry> trace,
  ) {
    const nodes = <(String, String, String)>[
      (
        'ON_ANTIRESORPTIVE_TREATMENT',
        'antiresorptiveTreatmentStatus',
        'Is the patient currently on antiresorptive treatment?',
      ),
      (
        'ANTIRESORPTIVE_TREATMENT_DURATION',
        'antiresorptiveTreatmentOver12Months',
        'Has the patient used the current antiresorptive treatment for more than 12 months?',
      ),
      (
        'TREATMENT_ADHERENCE',
        'adheredToTheTreatment',
        'Has the patient adhered to the treatment plan?',
      ),
      (
        'SYMPTOMATIC_FRACTURE',
        'symptomaticFractureInLast12M',
        'Has the patient had 1 or more symptomatic fractures in last 12 months?',
      ),
      (
        'MULTIPLE_FRACTURES',
        'multipleFractures',
        'Has the patient had 2 or more fractures? (Check for occult vertebral fractures in previous chest or abdomen scan)',
      ),
      (
        'LOW_BMD',
        'lowBMD',
        'Does the patient have a BMD T-score below -3.0 at any site?',
      ),
      (
        'PRIOR_MI_OR_STROKE',
        'priorMIorStroke',
        'Does the patient have a history of myocardial infarction(MI) or stroke?',
      ),
      (
        'SEQUENCING_FROM_DENOSUMAB',
        'sequencingFromDenosumab',
        'Sequencing from denosumab?',
      ),
    ];
    for (final node in nodes) {
      if (!facts.containsKey(node.$2)) {
        return PathwayQuestionStep(
          pathwayId: 'PATHWAY2',
          nodeId: node.$1,
          question: node.$3,
          requiredFacts: [node.$2],
          trace: List.unmodifiable(trace),
        );
      }
      trace.add(
        LivePathwayTraceEntry(
          nodeId: node.$1,
          pathwayId: 'PATHWAY2',
          nodeType: 'decision',
          matched: facts[node.$2] as bool,
          nextNodeId: null,
        ),
      );
      if (node.$2 == 'antiresorptiveTreatmentOver12Months' &&
          facts[node.$2] == false) {
        return CompletedPathwayEvaluation(
          pathwayId: 'PATHWAY2',
          trace: List.unmodifiable(trace),
          actions: const [
            {
              'type': 'recommendation',
              'recommendation':
                  'Review standard antiresorptive treatment options.',
            },
          ],
        );
      }
    }
    const action = 'Review ongoing treatment and sequencing options.';
    trace.add(
      const LivePathwayTraceEntry(
        nodeId: 'RESULT_P2',
        pathwayId: 'PATHWAY2',
        nodeType: 'result',
        actionsTriggered: [action],
      ),
    );
    return CompletedPathwayEvaluation(
      pathwayId: 'PATHWAY2',
      actions: const [
        {'type': 'recommendation', 'recommendation': action},
      ],
      trace: List.unmodifiable(trace),
    );
  }

  Map<String, dynamic> _liveResultJson(CompletedPathwayEvaluation result) => {
    'status': 'complete',
    'contractVersion': 'songyi-p1p2-20261008',
    'pathwayId': result.pathwayId,
    'actions': result.actions,
    'trace': result.trace
        .map(
          (entry) => {
            'nodeId': entry.nodeId,
            'pathwayId': entry.pathwayId,
            'nodeType': entry.nodeType,
            'matched': entry.matched,
            'nextNodeId': entry.nextNodeId,
            'actionsTriggered': entry.actionsTriggered,
          },
        )
        .toList(),
  };

  @override
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
    ClinicalResultsReview? resultsReview,
  }) async {
    _require(UserRole.clinician);
    final current = await fetchClinicalCase(assessment.id);
    final effectiveReview =
        resultsReview ??
        _resultsReviews[assessment.id] ??
        ClinicalResultsReview(
          commonAdvice: const ['Clinician-reviewed mock Common Advice.'],
          investigationRevision: 1,
          questionnaireRevision: 1,
          generatedAt: DateTime.now().toUtc(),
        );
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
        (decision == ClinicalCaseStatus.approved && notes.trim().isEmpty))
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
    if (decision == ClinicalCaseStatus.approved) {
      a['approved_common_advice'] = effectiveReview.commonAdvice;
      a['reviewed_at'] = DateTime.now().toUtc().toIso8601String();
    }
  }

  @override
  Future<ClinicalResultsReview?> getClinicalCaseResultsReview(
    String caseId,
  ) async {
    _requireAssignedCase(caseId, inProgress: false);
    return _resultsReviews[caseId];
  }

  @override
  Future<ClinicalResultsReview> generateClinicalCaseResultsReview({
    required String caseId,
    required int expectedInvestigationRevision,
    required int expectedQuestionnaireRevision,
  }) async {
    _requireAssignedCase(caseId, inProgress: false);
    final investigation = _investigations[caseId];
    if (investigation == null ||
        !investigation.canStartPathway ||
        investigation.revision != expectedInvestigationRevision) {
      throw const AppException(
        'Current complete Investigations are required for Common Advice.',
      );
    }
    final row = _cases[caseId]!;
    final response = _questionnaireResponses[row['patient_id']];
    if (response == null ||
        response.revision != expectedQuestionnaireRevision) {
      throw const AppException(
        'The questionnaire changed. Reload before generating Common Advice.',
      );
    }
    final review = ClinicalResultsReview.fromJson({
      'vitaminD': {'recommendation': 'Clinician-reviewed Vitamin D advice.'},
      'calcium': {'recommendation': 'Clinician-reviewed calcium advice.'},
      'protein': {'recommendation': null},
      'lifestyleAdvice': const [
        'Ceasing smoking',
        'Reducing alcohol intake',
        'Weight bearing exercises',
      ],
      'source': {
        'investigationRevision': investigation.revision,
        'questionnaireRevision': response.revision,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    });
    _resultsReviews[caseId] = review;
    return review;
  }

  @override
  Future<List<PatientApprovedResult>> fetchPatientApprovedResults() async {
    _require(UserRole.patient);
    return _cases.values
        .where(
          (row) => row['patient_id'] == _user.id && row['status'] == 'approved',
        )
        .map(
          (row) => PatientApprovedResult(
            caseId: row['id'].toString(),
            reviewedAt:
                DateTime.tryParse(row['reviewed_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            lifestyleRecommendations: List<String>.from(
              row['approved_common_advice'] as List? ?? const [],
            ),
            careRecommendations: (row['approved_actions'] as List? ?? const [])
                .map(
                  (value) => PathwayAction.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList(growable: false),
            clinicianMessage: row['decision_notes']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
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
  Future<QuestionnaireForm> fetchQuestionnaireForm() async {
    if (_user.role != UserRole.patient && !_user.isClinician) {
      throw const AppException('You cannot access this questionnaire.');
    }
    return buildMaturePatientForm(const [
      QuestionnaireQuestion(
        id: 'system-sex-row',
        fieldKey: 'sex',
        questionText: 'What is your sex?',
        type: QuestionType.singleChoice,
        options: ['Female', 'Male'],
        displayOrder: 1,
      ),
      QuestionnaireQuestion(
        id: 'system-postmenopausal-row',
        fieldKey: 'postmenopausal',
        questionText: 'Are you postmenopausal?',
        type: QuestionType.singleChoice,
        options: ['Yes', 'No'],
        displayOrder: 2,
      ),
      QuestionnaireQuestion(
        id: 'system-dairy-row',
        fieldKey: 'dietaryDairyServings',
        questionText: 'How many servings of dairy do you have per day?',
        type: QuestionType.numeric,
        displayOrder: 3,
      ),
      QuestionnaireQuestion(
        id: 'system-smoking-row',
        fieldKey: 'smoking',
        questionText: 'Do you currently smoke?',
        type: QuestionType.singleChoice,
        options: ['Yes', 'No'],
        displayOrder: 4,
      ),
      QuestionnaireQuestion(
        id: 'system-alcohol-row',
        fieldKey: 'alcohol',
        questionText: 'Do you currently drink alcohol?',
        type: QuestionType.singleChoice,
        options: ['Yes', 'No'],
        displayOrder: 5,
      ),
    ]);
  }

  @override
  Future<QuestionnaireResponse> submitQuestionnaireResponse({
    required Map<String, Object?> answers,
  }) async {
    _require(UserRole.patient);
    final profileSex = questionnaireSexFromProfile(_user.sexAtBirth);
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
    final unsupported = authoritativeAnswers.keys.where(
      (key) => !productionQuestionnaireAnswerKeys.contains(key),
    );
    if (unsupported.isNotEmpty) {
      throw const AppException(
        'This questionnaire contains an answer that is not approved for production submission.',
      );
    }
    final existing = _questionnaireResponses[_user.id];
    final response = QuestionnaireResponse(
      id: newId(),
      patientId: _user.id,
      status: QuestionnaireResponseStatus.submitted,
      revision: (existing?.revision ?? 0) + 1,
      submittedAt: DateTime.now().toUtc(),
      answers: Map.unmodifiable(authoritativeAnswers),
    );
    _questionnaireResponses[_user.id] = response;
    return response;
  }

  @override
  Future<QuestionnaireResponse?> fetchQuestionnaireResponse({
    required String patientId,
  }) async {
    if (_user.role == UserRole.patient && _user.id != patientId) {
      throw const AppException('You cannot access this questionnaire.');
    }
    if (_user.role == UserRole.clinician && !_user.isClinician) {
      throw const AppException('You cannot access this questionnaire.');
    }
    return _questionnaireResponses[patientId];
  }

  @override
  Future<List<MockQuestionnaireDraft>> fetchMockQuestionnaireDrafts() async {
    _require(UserRole.clinician);
    return List.unmodifiable(_questionnaireDrafts);
  }

  @override
  Future<MockQuestionnaireDraft> saveMockQuestionnaireDraft(
    MockQuestionnaireDraft q,
  ) async {
    _require(UserRole.clinician);
    final saved = q.presentationId.isEmpty
        ? q.copyWith(presentationId: newId())
        : q;
    _questionnaireDrafts.removeWhere(
      (x) => x.presentationId == saved.presentationId,
    );
    _questionnaireDrafts.add(saved);
    return saved;
  }

  @override
  Future<MockQuestionnaireDraft> markMockQuestionnaireDraftReady(
    String id,
  ) async {
    _require(UserRole.clinician);
    return saveMockQuestionnaireDraft(
      _questionnaireDrafts
          .firstWhere((q) => q.presentationId == id)
          .copyWith(state: MockQuestionnaireDraftState.ready),
    );
  }

  static Future<PathwayEvaluation> _evaluateLocally(ClinicalInput input) async {
    final facts = input.toFacts();
    final trace = <Map<String, Object?>>[];
    final actions = <Map<String, Object?>>[];

    Map<String, dynamic> finish(
      String? pathway,
      String decision,
      String reason, [
      List<String> missing = const [],
    ]) => {
      'pathway': pathway,
      'decision': decision,
      'routing_reason': reason,
      'rule_version': 'pathway1-2026-09-13.1',
      'actions': actions,
      'trace': trace,
      'missing_inputs': missing,
      'warnings': ['Decision support requires clinician review.'],
    };

    void addTrace(
      String id,
      bool? matched,
      String reason,
      Map<String, Object?> input,
    ) {
      trace.add({
        'rule_id': id,
        'matched': matched,
        'input': input,
        'reason': reason,
      });
    }

    final treated = facts['osteoporosisTreatmentStatus'];
    if (treated is! bool) {
      return PathwayEvaluation.fromJson(
        finish(
          null,
          'needs_more_information',
          'Treatment history has not been confirmed.',
          ['osteoporosisTreatmentStatus'],
        ),
      );
    }
    if (treated) {
      return PathwayEvaluation.fromJson(
        finish(
          'PATHWAY2',
          'not_integrated',
          'Previous or current osteoporosis treatment was recorded.',
        ),
      );
    }

    const routeReason =
        'No previous or current osteoporosis treatment was recorded.';
    final entryMissing = <String>[];
    final minimalTraumaFracture = facts['minimalTraumaFracture'];
    final sex = facts['sex'];
    final fractureSite = facts['fractureSite'];
    if (minimalTraumaFracture is! bool) {
      entryMissing.add('minimalTraumaFracture');
    }
    if (sex == 'female') {
      if (facts['postmenopausal'] is! bool) entryMissing.add('postmenopausal');
    } else if (sex == 'male') {
      if (facts['age'] is! num) entryMissing.add('age');
    } else {
      entryMissing.add('sex');
    }
    if (fractureSite is! String || fractureSite.isEmpty) {
      entryMissing.add('fractureSite');
    }

    final entryInput = {
      'osteoporosisTreatmentStatus': treated,
      'minimalTraumaFracture': minimalTraumaFracture,
      'sex': sex,
      'postmenopausal': facts['postmenopausal'],
      'age': facts['age'],
      'fractureSite': fractureSite,
    };
    if (entryMissing.isNotEmpty) {
      addTrace(
        'ENTRY',
        null,
        'Pathway entry conditions: information needed.',
        entryInput,
      );
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'needs_more_information', routeReason, entryMissing),
      );
    }

    final entryMatched =
        minimalTraumaFracture == true &&
        (sex == 'female'
            ? facts['postmenopausal'] == true
            : sex == 'male' && (facts['age'] as num) >= 50) &&
        !['hand', 'foot', 'face', 'ankle'].contains(fractureSite);
    addTrace(
      'ENTRY',
      entryMatched,
      'Pathway entry conditions: ${entryMatched ? 'met' : 'not met'}.',
      entryInput,
    );
    if (!entryMatched) {
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'not_applicable', routeReason),
      );
    }

    bool? requireBool(String key) =>
        facts[key] is bool ? facts[key] as bool : null;
    num? requireNum(String key) => facts[key] is num ? facts[key] as num : null;

    PathwayEvaluation? missingRule(
      String id,
      String label,
      Map<String, Object?> input,
      List<String> missing,
    ) {
      addTrace(id, null, '$label: information needed.', input);
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'needs_more_information', routeReason, missing),
      );
    }

    var evaluationInput = {
      'sex': sex,
      'postmenopausal': facts['postmenopausal'],
      'yearSincePostmenopausal': facts['yearSincePostmenopausal'],
      'minimalTraumaFracture': minimalTraumaFracture,
      'isRobustWoman': facts['isRobustWoman'],
    };
    final menopauseRelevant =
        sex == 'female' &&
        facts['postmenopausal'] == true &&
        requireNum('yearSincePostmenopausal') != null &&
        requireNum('yearSincePostmenopausal')! <= 10 &&
        minimalTraumaFracture == true;
    if (sex == 'female' &&
        facts['postmenopausal'] == true &&
        facts['yearSincePostmenopausal'] == null) {
      return missingRule(
        'MENOPAUSAL_HORMONAL_THERAPY',
        'Menopause and treatment consideration',
        evaluationInput,
        ['yearSincePostmenopausal'],
      )!;
    }
    if (menopauseRelevant && facts['isRobustWoman'] == null) {
      return missingRule(
        'MENOPAUSAL_HORMONAL_THERAPY',
        'Menopause and treatment consideration',
        evaluationInput,
        ['isRobustWoman'],
      )!;
    }
    final menopauseMatched =
        menopauseRelevant && facts['isRobustWoman'] == true;
    addTrace(
      'MENOPAUSAL_HORMONAL_THERAPY',
      menopauseMatched,
      'Menopause and treatment consideration: ${menopauseMatched ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (menopauseMatched) {
      actions.add({
        'type': 'consideration',
        'recommendation': 'Consider menopausal hormonal therapy',
        'requireReview': true,
      });
    }

    evaluationInput = {'eGFR': facts['eGFR']};
    final egfr = requireBool('eGFR');
    if (egfr == null) {
      return missingRule(
        'RENAL_DYSFUNCTION',
        'Kidney function condition',
        evaluationInput,
        ['eGFR'],
      )!;
    }
    final renalMatched = !egfr;
    addTrace(
      'RENAL_DYSFUNCTION',
      renalMatched,
      'Kidney function condition: ${renalMatched ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (renalMatched) {
      actions.add({
        'type': 'referral',
        'destination': 'SPECIALIST',
        'reason':
            'Antiresorptive therapy may increase risk of hypocalcaemia in presence of significant renal dysfunction',
      });
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {'osteoporosisTreatmentStatus': treated};
    addTrace(
      'ON_OSTEOPOROSIS_TREATMENT',
      false,
      'Previous osteoporosis treatment: not met.',
      evaluationInput,
    );

    evaluationInput = {
      'liveInResidentialCare': facts['liveInResidentialCare'],
      'clinicalFrailtyScore': facts['clinicalFrailtyScore'],
      'lifeExpectancy': facts['lifeExpectancy'],
    };
    final residentialCare = requireBool('liveInResidentialCare');
    final frailty = requireNum('clinicalFrailtyScore');
    final lifeExpectancy = requireNum('lifeExpectancy');
    final careMissing = <String>[
      if (residentialCare == null) 'liveInResidentialCare',
      if (frailty == null) 'clinicalFrailtyScore',
      if (lifeExpectancy == null) 'lifeExpectancy',
    ];
    if (careMissing.isNotEmpty) {
      return missingRule(
        'RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY',
        'Care setting, frailty and life expectancy',
        evaluationInput,
        careMissing,
      )!;
    }
    final careMatched =
        residentialCare == true || frailty! >= 6 || lifeExpectancy! < 7;
    addTrace(
      'RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY',
      careMatched,
      'Care setting, frailty and life expectancy: ${careMatched ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (careMatched) {
      actions.addAll([
        {
          'type': 'medication',
          'medication': 'Denosumab',
          'dose': '60mg',
          'route': 'subcut',
          'frequency': '6 monthly',
          'requireReview': true,
        },
        {'type': 'followUp', 'destination': 'GP'},
      ]);
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {
      'knownPoorMedicationAdherence': facts['knownPoorMedicationAdherence'],
      'cognitiveImpairment': facts['cognitiveImpairment'],
    };
    final poorAdherence = requireBool('knownPoorMedicationAdherence');
    final cognitiveImpairment = requireBool('cognitiveImpairment');
    final adherenceMissing = <String>[
      if (poorAdherence == null) 'knownPoorMedicationAdherence',
      if (cognitiveImpairment == null) 'cognitiveImpairment',
    ];
    if (adherenceMissing.isNotEmpty) {
      return missingRule(
        'ADHERENCE_CONCERN',
        'Medication adherence or cognitive impairment',
        evaluationInput,
        adherenceMissing,
      )!;
    }
    final adherenceMatched =
        poorAdherence == true || cognitiveImpairment == true;
    addTrace(
      'ADHERENCE_CONCERN',
      adherenceMatched,
      'Medication adherence or cognitive impairment: ${adherenceMatched ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (adherenceMatched) {
      actions.addAll([
        {
          'type': 'treatmentOptions',
          'options': [
            {
              'medication': 'Zoledronic acid',
              'dose': '5mg',
              'route': 'IV infusion',
              'frequency': 'yearly',
              'duration': '3 years',
            },
            {
              'medication': 'Risedronate EC',
              'dose': '35mg',
              'route': 'oral',
              'frequency': 'weekly',
            },
          ],
          'requireReview': true,
        },
        {'type': 'followUp', 'destination': 'GP'},
        {
          'type': 'review',
          'instruction':
              'Reassess fracture risk after 5 years or after 3 zoledronic acid doses',
        },
      ]);
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {
      'testAvailable': facts['testAvailable'],
      'testWithinLast2Years': facts['testWithinLast2Years'],
    };
    final testAvailable = requireBool('testAvailable');
    if (testAvailable == null) {
      return missingRule(
        'DXA_NOT_WITHIN_2YEARS',
        'Bone density test timing',
        evaluationInput,
        ['testAvailable'],
      )!;
    }
    final dxaNotRecent =
        testAvailable == true && facts['testWithinLast2Years'] == false;
    if (testAvailable == true && facts['testWithinLast2Years'] is! bool) {
      return missingRule(
        'DXA_NOT_WITHIN_2YEARS',
        'Bone density test timing',
        evaluationInput,
        ['testWithinLast2Years'],
      )!;
    }
    addTrace(
      'DXA_NOT_WITHIN_2YEARS',
      dxaNotRecent,
      'Bone density test timing: ${dxaNotRecent ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (dxaNotRecent) {
      actions.add({
        'type': 'investigation',
        'action':
            'Referral for BMD DXA scan (femoral neck or hip or lumbar spine)',
      });
    }

    evaluationInput = {'testAvailable': testAvailable};
    final dxaUnavailable = testAvailable == false;
    addTrace(
      'DXA_DISAVAILABLE',
      dxaUnavailable,
      'Bone density test availability: ${dxaUnavailable ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (dxaUnavailable) {
      actions.addAll([
        _standardTreatmentOptions(),
        {'type': 'followUp', 'destination': 'GP'},
        {
          'type': 'review',
          'instruction':
              'Review fracture risk after 5 years or after 3 zoledronic acid doses',
        },
        {
          'type': 'referral',
          'destination': 'FRAGILE BONE CLINIC',
          'when': 'After a maximum of 10 years of treatment',
        },
        {'type': 'pathwayRedirect', 'targetPathway': 'PATHWAY4'},
      ]);
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {'T-score': facts['T-score']};
    final tScore = requireNum('T-score');
    if (tScore == null) {
      return missingRule('T_SCORE', 'Bone density condition', evaluationInput, [
        'T-score',
      ])!;
    }
    final tScoreMatched = tScore > -2.5;
    addTrace(
      'T_SCORE',
      tScoreMatched,
      'Bone density condition: ${tScoreMatched ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (tScoreMatched) {
      actions.add(_standardTreatmentOptions());
      actions.addAll([
        {'type': 'followUp', 'destination': 'GP'},
        {
          'type': 'review',
          'instruction':
              'Review fracture risk after 5 years or after 3 zoledronic acid doses',
        },
        {
          'type': 'referral',
          'destination': 'FRAGILE BONE CLINIC',
          'when': 'After a maximum of 10 years of treatment',
        },
        {'type': 'pathwayRedirect', 'targetPathway': 'PATHWAY4'},
      ]);
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {
      'hipVertebralOrMultipleFracturesInLast24M':
          facts['hipVertebralOrMultipleFracturesInLast24M'],
    };
    final recentMajor = requireBool('hipVertebralOrMultipleFracturesInLast24M');
    if (recentMajor == null) {
      return missingRule(
        'RECENT_MAJOR_FRACTURES',
        'Recent major fractures',
        evaluationInput,
        ['hipVertebralOrMultipleFracturesInLast24M'],
      )!;
    }
    addTrace(
      'RECENT_MAJOR_FRACTURES',
      recentMajor,
      'Recent major fractures: ${recentMajor ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (recentMajor) {
      actions.addAll(_fragileBoneActions());
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    evaluationInput = {
      'hipVertebralOrMultipleFracturesInLast24M': recentMajor,
      'highRisk': facts['highRisk'],
    };
    final highRisk = requireBool('highRisk');
    if (highRisk == null) {
      return missingRule(
        'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE',
        'Very high fracture risk clinician confirmation',
        evaluationInput,
        ['highRisk'],
      )!;
    }
    addTrace(
      'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE',
      highRisk,
      'Very high fracture risk clinician confirmation: ${highRisk ? 'met' : 'not met'}.',
      evaluationInput,
    );
    if (highRisk) {
      actions.addAll(_fragileBoneActions());
      return PathwayEvaluation.fromJson(
        finish('PATHWAY1', 'action_taken', routeReason),
      );
    }

    addTrace(
      'STANDARD_OPTIONS_WITHOUT_RECENT_MAJOR_FRACTURE',
      true,
      'Very high fracture risk not confirmed after no recent major fracture: met.',
      evaluationInput,
    );
    actions.addAll([
      _standardTreatmentOptions(),
      {'type': 'followUp', 'destination': 'GP'},
      {
        'type': 'review',
        'instruction':
            'Review fracture risk after 5 years or after 3 zoledronic acid doses',
      },
    ]);
    return PathwayEvaluation.fromJson(
      finish('PATHWAY1', 'action_taken', routeReason),
    );
  }

  static Map<String, Object?> _standardTreatmentOptions() => {
    'type': 'treatmentOptions',
    'options': [
      {
        'medication': 'Zoledronic acid',
        'dose': '5mg',
        'route': 'IV infusion',
        'frequency': 'yearly',
        'duration': '3 years',
      },
      {
        'medication': 'Risedronate EC',
        'dose': '35mg',
        'route': 'oral',
        'frequency': 'weekly',
      },
      {
        'medication': 'Denosumab',
        'dose': '60mg',
        'route': 'subcut',
        'frequency': '6 monthly',
      },
    ],
    'requireReview': true,
  };

  static List<Map<String, Object?>> _fragileBoneActions() => [
    {
      'type': 'consideration',
      'recommendation': 'Consider commencement of osteoanabolic therapy',
      'requireReview': true,
    },
    {
      'type': 'referral',
      'destination': 'FRAGILE BONE CLINIC',
      'reason': 'Specialist input',
    },
  ];
}
