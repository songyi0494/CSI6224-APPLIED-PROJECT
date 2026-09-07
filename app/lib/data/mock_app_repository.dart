import 'dart:math';

import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';
import '../models/questionnaire.dart';
import 'app_repository.dart';

class MockAppRepository implements AppRepository {
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
        'hipVertebralOrMultipleFracturesInLast24M': true,
        'highRisk': true,
      },
    ),
  ];

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
          role == UserRole.clinician ? 'Dr Demo Clinician' : 'Demo Patient',
      email: email,
      role: role,
    );
  }

  @override
  Future<List<Questionnaire>> fetchQuestionnaires() async {
    return const [
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
    ];
  }

  @override
  Future<List<PatientResponse>> fetchPatientResponses() async {
    return [
      PatientResponse(
        id: 'response-1',
        patientName: 'Avery Martin',
        questionnaireTitle: 'Falls and Bone Health Check',
        submittedAt: DateTime.now().subtract(const Duration(hours: 4)),
        answers: const {
          'falls_12_months': 2,
          'fear_of_falling': true,
          'medication_notes': 'No current osteoporosis treatment.',
        },
      ),
    ];
  }

  @override
  Future<List<ClinicalCase>> fetchClinicalCases() async {
    return List<ClinicalCase>.unmodifiable(_cases);
  }

  @override
  Future<ClinicalCase> saveClinicalCase(ClinicalCase clinicalCase) async {
    final existing = _cases.indexWhere((item) => item.id == clinicalCase.id);
    final saved = clinicalCase.id.isEmpty
        ? clinicalCase.copyWith(id: 'case-${1000 + Random().nextInt(8999)}')
        : clinicalCase;
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

    if (clinicalCase.pathway == ClinicalPathway.pathway2) {
      return const PathwayEvaluation(
        pathway: 'PATHWAY2',
        decision: 'requires_rule_engine',
        actions: [
          PathwayAction(
            type: 'integrationGap',
            description:
                'Pathway 2 UI is ready. Backend rule function is still required.',
            raw: {'type': 'integrationGap'},
          ),
        ],
        trace: ['PATHWAY2_UI_READY', 'BACKEND_FUNCTION_PENDING'],
      );
    }

    final facts = clinicalCase.facts;
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
    );
  }

  @override
  Future<void> recordClinicianDecision({
    required String caseId,
    required ClinicalCaseStatus decision,
    required String notes,
  }) async {
    final index = _cases.indexWhere((item) => item.id == caseId);
    if (index >= 0) {
      _cases[index] = _cases[index].copyWith(status: decision);
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
}
