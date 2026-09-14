import 'dart:async';
import 'dart:convert';
import '../utils/new_id.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../models/pathway1_clinician_input.dart';
import '../models/pathway_evaluation.dart';
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
    final patient = _users[patientId]!;
    final input = ClinicalInput(
      treated: treated,
      age: _ageFromDateOfBirth(patient.dateOfBirth),
      sexAtBirth: patient.sexAtBirth,
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
    final egfr = requireNum('eGFR');
    if (egfr == null) {
      return missingRule(
        'RENAL_DYSFUNCTION',
        'Kidney function condition',
        evaluationInput,
        ['eGFR'],
      )!;
    }
    final renalMatched = egfr < 30;
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
