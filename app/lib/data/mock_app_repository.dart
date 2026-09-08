import '../models/app_user.dart';
import '../models/approved_recommendation.dart';
import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';
import '../models/questionnaire.dart';
import 'app_repository.dart';

class MockAppRepository implements AppRepository {
  static final DateTime _sampleSubmittedAt = DateTime(2026, 9, 8, 3);

  int _nextCaseNumber = 1002;

  final List<ClinicalCase> _cases = [
    const ClinicalCase(
      id: 'case-1001',
      patientName: 'Avery Martin',
      pathway: ClinicalPathway.pathway1,
      status: ClinicalCaseStatus.draft,
      facts: {
        'osteoporosisTreatmentStatus': false,
        'minimalTraumaFracture': true,
        'sex': 'female',
        'postmenopausal': true,
        'age': 74,
        'fractureSite': 'hip',
        'eGFR': 54,
        'liveInResidentialCare': false,
        'clinicalFrailtyScore': 4,
        'lifeExpectancy': 10,
        'knownPoorMedicationAdherence': false,
        'cognitiveImpairment': false,
        'testAvailable': true,
        'testWithinLast2Years': true,
        'T-score': -2.7,
        'vitaminDLevel': 65,
        'hipVertebralOrMultipleFracturesInLast24M': true,
        'highRisk': true,
        'historyOfMiOrStroke': false,
      },
    ),
  ];

  final List<Questionnaire> _questionnaires = const [
    Questionnaire(
      id: 'falls-risk',
      title: 'Falls and Bone Health Check',
      status: QuestionnaireStatus.published,
      questions: [
        QuestionDefinition(
          id: 'falls_12_months',
          prompt: 'How many falls have you had in the last 12 months?',
          type: QuestionType.number,
        ),
        QuestionDefinition(
          id: 'fear_of_falling',
          prompt: 'Are you worried about falling?',
          type: QuestionType.yesNo,
        ),
        QuestionDefinition(
          id: 'medication_notes',
          prompt: 'List any current osteoporosis medicines.',
          type: QuestionType.text,
          required: false,
        ),
      ],
    ),
  ].toList();

  final List<PatientResponse> _responses = [
    PatientResponse(
      id: 'response-1',
      questionnaireId: 'falls-risk',
      patientName: 'Avery Martin',
      questionnaireTitle: 'Falls and Bone Health Check',
      submittedAt: _sampleSubmittedAt,
      answers: const {
        'falls_12_months': 2,
        'fear_of_falling': true,
        'medication_notes': 'No current osteoporosis treatment.',
      },
    ),
  ];

  final List<ApprovedRecommendation> _approvedRecommendations = [];

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return AppUser(
      id: role == UserRole.clinician ? 'clinician-demo' : 'patient-demo',
      displayName:
          role == UserRole.clinician ? 'Dr Demo Clinician' : 'Avery Martin',
      email: email,
      role: role,
    );
  }

  @override
  Future<List<Questionnaire>> fetchQuestionnaires() async {
    return List<Questionnaire>.unmodifiable(_questionnaires);
  }

  @override
  Future<Questionnaire> saveQuestionnaire(Questionnaire questionnaire) async {
    final saved = questionnaire.id.isEmpty
        ? questionnaire.copyWith(
            id: 'questionnaire-${_questionnaires.length + 1}')
        : questionnaire;
    final index = _questionnaires.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      _questionnaires[index] = saved;
    } else {
      _questionnaires.add(saved);
    }
    return saved;
  }

  @override
  Future<Questionnaire> publishQuestionnaire(String questionnaireId) async {
    final index = _questionnaires.indexWhere(
      (item) => item.id == questionnaireId,
    );
    if (index < 0) {
      throw StateError('Questionnaire not found');
    }
    final published = _questionnaires[index].copyWith(
      status: QuestionnaireStatus.published,
    );
    _questionnaires[index] = published;
    return published;
  }

  @override
  Future<List<PatientResponse>> fetchPatientResponses() async {
    return List<PatientResponse>.unmodifiable(_responses);
  }

  @override
  Future<PatientResponse> submitPatientResponse({
    required String questionnaireId,
    required String patientName,
    required Map<String, Object?> answers,
  }) async {
    final questionnaire = _questionnaires.firstWhere(
      (item) => item.id == questionnaireId,
    );
    final response = PatientResponse(
      id: 'response-${_responses.length + 1}',
      questionnaireId: questionnaireId,
      patientName: patientName,
      questionnaireTitle: questionnaire.title,
      submittedAt: DateTime.now(),
      answers: answers,
    );
    _responses.insert(0, response);
    return response;
  }

  @override
  Future<List<ClinicalCase>> fetchClinicalCases() async {
    return List<ClinicalCase>.unmodifiable(_cases);
  }

  @override
  Future<ClinicalCase?> fetchClinicalCase(String caseId) async {
    for (final clinicalCase in _cases) {
      if (clinicalCase.id == caseId) {
        return clinicalCase;
      }
    }
    return null;
  }

  @override
  Future<List<ApprovedRecommendation>> fetchApprovedRecommendations({
    required String patientName,
  }) async {
    final normalisedName = patientName.trim().toLowerCase();
    return _approvedRecommendations
        .where(
            (item) => item.patientName.trim().toLowerCase() == normalisedName)
        .toList(growable: false);
  }

  @override
  Future<ClinicalCase> saveClinicalCase(ClinicalCase clinicalCase) async {
    final saved = clinicalCase.id.isEmpty
        ? clinicalCase.copyWith(id: 'case-${_nextCaseNumber++}')
        : clinicalCase;
    final existing = _cases.indexWhere((item) => item.id == saved.id);
    if (existing >= 0) {
      _cases[existing] = saved;
    } else {
      _cases.add(saved);
    }
    return saved;
  }

  @override
  Future<PathwayEvaluation> evaluatePathway(ClinicalCase clinicalCase) async {
    final missing = _missingRequiredFacts(clinicalCase);
    if (missing.isNotEmpty) {
      return PathwayEvaluation(
        pathway: clinicalCase.pathway.name,
        decision: 'needs_more_information',
        actions: const [],
        trace: const ['LOCAL_VALIDATION_FAILED'],
        missingInputs: missing,
        warning: 'The system must not infer missing clinical inputs.',
      );
    }

    final facts = clinicalCase.facts;
    final unsafe = _unsafeInputs(facts);
    if (clinicalCase.pathway == ClinicalPathway.pathway2) {
      return PathwayEvaluation(
        pathway: 'PATHWAY2',
        decision: 'requires_rule_engine',
        actions: const [
          PathwayAction(
            type: 'integrationGap',
            description:
                'Pathway 2 UI is ready. Backend rule function is still required.',
            raw: {'type': 'integrationGap'},
          ),
        ],
        trace: const ['PATHWAY2_UI_READY', 'BACKEND_FUNCTION_PENDING'],
        unsafeInputs: unsafe,
        warning: _warningFor(unsafe),
      );
    }

    final trace = <String>['ENTRY_CONDITION_PASSED'];
    final actions = <PathwayAction>[];

    if (facts['osteoporosisTreatmentStatus'] == true) {
      return const PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'action_taken',
        actions: [
          PathwayAction(
            type: 'pathwayRedirect',
            description: 'Redirect to PATHWAY2',
            raw: {'type': 'pathwayRedirect', 'targetPathway': 'PATHWAY2'},
          ),
        ],
        trace: ['ENTRY_CONDITION_FAILED', 'ON_OSTEOPOROSIS_TREATMENT'],
      );
    }

    if (facts['minimalTraumaFracture'] != true) {
      return const PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'not_applicable',
        actions: [],
        trace: ['ENTRY_CONDITION_FAILED'],
      );
    }

    final eGfr = _asDouble(facts['eGFR']);
    if (eGfr != null && eGfr < 30) {
      trace.add('RENAL_DYSFUNCTION');
      actions.add(
        const PathwayAction(
          type: 'referral',
          description:
              'Refer to specialist due to significant renal dysfunction risk.',
          raw: {'type': 'referral', 'destination': 'SPECIALIST'},
        ),
      );
      return PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'action_taken',
        actions: actions,
        trace: trace,
        unsafeInputs: unsafe,
        warning: _warningFor(unsafe),
      );
    }

    final frailty = _asDouble(facts['clinicalFrailtyScore']) ?? 0;
    final lifeExpectancy = _asDouble(facts['lifeExpectancy']) ?? 99;
    if (facts['liveInResidentialCare'] == true ||
        frailty >= 6 ||
        lifeExpectancy < 7) {
      trace.add('RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY');
      actions.addAll(const [
        PathwayAction(
          type: 'medication',
          description: 'Denosumab, 60mg, subcut, 6 monthly',
          raw: {'type': 'medication', 'medication': 'Denosumab'},
        ),
        PathwayAction(
          type: 'followUp',
          description: 'Follow up with GP.',
          raw: {'type': 'followUp', 'destination': 'GP'},
        ),
      ]);
      return PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'action_taken',
        actions: actions,
        trace: trace,
        unsafeInputs: unsafe,
        warning: _warningFor(unsafe),
      );
    }

    if (facts['knownPoorMedicationAdherence'] == true ||
        facts['cognitiveImpairment'] == true) {
      trace.add('ADHERENCE_CONCERN');
      actions.addAll(const [
        PathwayAction(
          type: 'treatmentOptions',
          description:
              'Review zoledronic acid or risedronate options with GP follow-up.',
          raw: {'type': 'treatmentOptions'},
        ),
        PathwayAction(
          type: 'review',
          description:
              'Reassess fracture risk after 5 years or after 3 zoledronic acid doses.',
          raw: {'type': 'review'},
        ),
      ]);
      return PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'action_taken',
        actions: actions,
        trace: trace,
        unsafeInputs: unsafe,
        warning: _warningFor(unsafe),
      );
    }

    if (facts['testAvailable'] == false) {
      trace.add('DXA_DISAVAILABLE');
      actions.add(
        const PathwayAction(
          type: 'treatmentOptions',
          description:
              'DXA impractical. Review PBS-funded antiresorptive treatment options.',
          raw: {'type': 'treatmentOptions'},
        ),
      );
      return PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'action_taken',
        actions: actions,
        trace: trace,
        unsafeInputs: unsafe,
        warning: _warningFor(unsafe),
      );
    }

    if (facts['testWithinLast2Years'] == false) {
      trace.add('DXA_NOT_WITHIN_2YEARS');
      actions.add(
        const PathwayAction(
          type: 'investigation',
          description: 'Referral for BMD DXA scan.',
          raw: {'type': 'investigation'},
        ),
      );
    }

    if (facts['hipVertebralOrMultipleFracturesInLast24M'] == true ||
        facts['highRisk'] == true) {
      trace.add('RECENT_MAJOR_FRACTURES');
      actions.addAll(const [
        PathwayAction(
          type: 'consideration',
          description: 'Consider commencement of osteoanabolic therapy.',
          raw: {'type': 'consideration'},
        ),
        PathwayAction(
          type: 'referral',
          description: 'Refer to fragile bone clinic for specialist input.',
          raw: {'type': 'referral', 'destination': 'FRAGILE BONE CLINIC'},
        ),
      ]);
    } else {
      trace.add('STANDARD_ANTIRESORPTIVE_OPTIONS');
      actions.add(
        const PathwayAction(
          type: 'treatmentOptions',
          description:
              'Review zoledronic acid, risedronate EC, or denosumab options.',
          raw: {'type': 'treatmentOptions'},
        ),
      );
    }

    return PathwayEvaluation(
      pathway: 'PATHWAY1',
      decision: 'action_taken',
      actions: actions,
      trace: trace,
      unsafeInputs: unsafe,
      warning: _warningFor(unsafe),
    );
  }

  @override
  Future<void> recordClinicianDecision({
    required String caseId,
    required ClinicalCaseStatus decision,
    required String notes,
    String? recommendationSummary,
  }) async {
    final index = _cases.indexWhere((item) => item.id == caseId);
    if (index >= 0) {
      final clinicalCase = _cases[index].copyWith(status: decision);
      _cases[index] = clinicalCase;
      _approvedRecommendations.removeWhere((item) => item.caseId == caseId);
      if (decision == ClinicalCaseStatus.approved) {
        _approvedRecommendations.insert(
          0,
          ApprovedRecommendation(
            id: 'approved-$caseId',
            caseId: caseId,
            patientName: clinicalCase.patientName,
            pathway: clinicalCase.pathway,
            summary: recommendationSummary ??
                'Clinician-approved osteoporosis recommendation recorded.',
            clinicianNotes: notes,
            approvedAt: DateTime.now(),
          ),
        );
      }
    }
  }

  List<String> _missingRequiredFacts(ClinicalCase clinicalCase) {
    final facts = clinicalCase.facts;
    const required = [
      'osteoporosisTreatmentStatus',
      'minimalTraumaFracture',
      'sex',
      'age',
      'fractureSite',
      'eGFR',
      'vitaminDLevel',
    ];
    return required
        .where((key) => facts[key] == null || facts[key] == '')
        .toList();
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  List<String> _unsafeInputs(Map<String, Object?> facts) {
    final unsafe = <String>[];
    final eGfr = _asDouble(facts['eGFR']);
    final vitaminD = _asDouble(facts['vitaminDLevel']);
    if (eGfr != null && eGfr < 30) {
      unsafe.add('eGFR below 30: specialist review required.');
    }
    if (vitaminD != null && vitaminD < 50) {
      unsafe.add('Vitamin D below target range: clinician review required.');
    }
    if (facts['historyOfMiOrStroke'] == true) {
      unsafe.add(
          'MI or stroke history reported: review before treatment choice.');
    }
    return unsafe;
  }

  String? _warningFor(List<String> unsafeInputs) {
    if (unsafeInputs.isEmpty) {
      return null;
    }
    return 'Review cautionary clinical inputs before recording a decision.';
  }
}
