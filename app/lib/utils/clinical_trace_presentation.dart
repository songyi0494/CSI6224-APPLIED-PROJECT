import '../models/pathway1_clinician_input.dart';
import '../models/pathway_evaluation.dart';
import 'clinical_labels.dart';

class ClinicalTracePresentation {
  const ClinicalTracePresentation({
    required this.title,
    required this.details,
    required this.result,
    required this.technicalRuleId,
    this.implication,
  });

  final String title;
  final List<String> details;
  final String result;
  final String? implication;
  final String technicalRuleId;
}

ClinicalTracePresentation clinicalTracePresentation(
  ReasoningTraceEntry trace, {
  Pathway1ClinicianInput? clinicianInput,
}) {
  final input = trace.input;
  switch (trace.ruleId) {
    case 'ENTRY':
      return ClinicalTracePresentation(
        title: 'Pathway eligibility',
        details: [
          _line('Minimal-trauma fracture', input['minimalTraumaFracture']),
          _line('Sex at birth', input['sex']),
          _line('Postmenopausal', input['postmenopausal']),
          _line('Fracture site', input['fractureSite']),
        ],
        result: _result(
          trace,
          yes: 'Pathway 1 entry criteria met.',
          no: 'Pathway 1 entry criteria not met.',
          unknown: 'More information is needed to confirm entry criteria.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'MENOPAUSAL_HORMONAL_THERAPY':
      return ClinicalTracePresentation(
        title: 'Menopausal hormone therapy consideration',
        details: [
          _line('Years since menopause', input['yearSincePostmenopausal']),
          'Pathway consideration: within 10 years of menopause',
          if (input['isRobustWoman'] != null)
            _line('Robustness confirmed by clinician', input['isRobustWoman']),
        ],
        result: _result(
          trace,
          yes: 'MHT consideration criterion triggered.',
          no: 'MHT consideration criterion not triggered.',
          unknown: 'More menopause-related information is needed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'RENAL_DYSFUNCTION':
      return ClinicalTracePresentation(
        title: 'Kidney function',
        details: [
          _line('eGFR', input['eGFR'], suffix: ' mL/min'),
          'Renal referral threshold: eGFR < 30 mL/min',
        ],
        result: _result(
          trace,
          yes: 'Renal referral criterion triggered.',
          no: 'Renal referral criterion not triggered.',
          unknown:
              'Kidney function is needed before this criterion can be assessed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'ON_OSTEOPOROSIS_TREATMENT':
      return ClinicalTracePresentation(
        title: 'Previous osteoporosis treatment',
        details: [
          _line(
            'Current or previous osteoporosis treatment',
            input['osteoporosisTreatmentStatus'],
          ),
        ],
        result: _result(
          trace,
          yes: 'Previous treatment branch triggered.',
          no: 'Treatment-naive pathway continues.',
          unknown: 'Treatment history is needed before routing can continue.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY':
      return ClinicalTracePresentation(
        title: 'Frailty / care setting',
        details: [
          _line('Residential aged care', input['liveInResidentialCare']),
          _line('Clinical Frailty Score', input['clinicalFrailtyScore']),
          'Severe frailty threshold: >= 6',
          _line('Life expectancy', input['lifeExpectancy'], suffix: ' years'),
          'Short life expectancy threshold: < 7 years',
        ],
        result: _result(
          trace,
          yes: 'Frailty / care-setting treatment branch triggered.',
          no: 'Frailty / care-setting treatment branch not triggered.',
          unknown:
              'Frailty, care setting, or life expectancy information is needed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'ADHERENCE_CONCERN':
      return ClinicalTracePresentation(
        title: 'Medication adherence',
        details: [
          _line(
            'Known poor medication adherence',
            input['knownPoorMedicationAdherence'],
          ),
          _line('Cognitive impairment', input['cognitiveImpairment']),
        ],
        result: _result(
          trace,
          yes: 'Adherence-concern branch triggered.',
          no: 'Adherence-concern branch not triggered.',
          unknown: 'Adherence and cognition information is needed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'DXA_NOT_WITHIN_2YEARS':
      return ClinicalTracePresentation(
        title: 'DXA timing',
        details: [
          _line('DXA within previous 2 years', input['testWithinLast2Years']),
        ],
        result: _result(
          trace,
          yes: 'A new DXA is required by this criterion.',
          no: 'A new DXA is not required by this criterion.',
          unknown:
              'DXA timing is needed before this criterion can be assessed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'DXA_DISAVAILABLE':
      return ClinicalTracePresentation(
        title: 'DXA practicality',
        details: [
          _line('DXA available for decision-making', input['testAvailable']),
        ],
        result: _result(
          trace,
          yes:
              'DXA is unavailable or impractical; non-DXA pathway actions apply.',
          no: 'DXA-based decision pathway can continue.',
          unknown:
              'DXA availability is needed before this criterion can be assessed.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'T_SCORE':
      return ClinicalTracePresentation(
        title: 'Bone density',
        details: [
          _line('T-score', input['T-score']),
          if (clinicianInput?.tScoreSite != null)
            'Site: ${_siteText(clinicianInput!.tScoreSite!)}',
          'Clinical pathway threshold: <= -2.5',
        ],
        result: trace.matched == false
            ? 'Osteoporosis BMD threshold met.'
            : trace.matched == true
            ? 'Osteoporosis BMD threshold not met by this criterion.'
            : 'T-score is needed before this criterion can be assessed.',
        implication: trace.matched == false
            ? 'Continue to recent major fracture assessment.'
            : null,
        technicalRuleId: trace.ruleId,
      );
    case 'RECENT_MAJOR_FRACTURES':
      return ClinicalTracePresentation(
        title: 'Recent fracture severity',
        details: [
          _line(
            'Hip / vertebral / >=2 fractures within 24 months',
            input['hipVertebralOrMultipleFracturesInLast24M'],
          ),
        ],
        result: _result(
          trace,
          yes: 'Recent major fracture criterion met.',
          no: 'Recent major fracture criterion not met.',
          unknown: 'Recent fracture severity information is needed.',
        ),
        implication: trace.matched == true
            ? 'Consider osteoanabolic therapy and specialist referral.'
            : null,
        technicalRuleId: trace.ruleId,
      );
    case 'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE':
      return ClinicalTracePresentation(
        title: 'Clinician-confirmed very high fracture risk',
        details: [
          _line(
            'Recent major fracture criterion met',
            input['hipVertebralOrMultipleFracturesInLast24M'],
          ),
          _line('Very high fracture risk confirmed', input['highRisk']),
        ],
        result: _result(
          trace,
          yes: 'Very high fracture risk branch triggered.',
          no: 'Very high fracture risk branch not triggered.',
          unknown: 'Additional clinician confirmation is required.',
        ),
        technicalRuleId: trace.ruleId,
      );
    case 'STANDARD_OPTIONS_WITHOUT_RECENT_MAJOR_FRACTURE':
      return ClinicalTracePresentation(
        title: 'Standard treatment options',
        details: [
          _line('Very high fracture risk confirmed', input['highRisk']),
        ],
        result: 'Standard treatment options branch applies.',
        technicalRuleId: trace.ruleId,
      );
    default:
      return ClinicalTracePresentation(
        title: clinicalLabel(trace.ruleId),
        details: input.entries
            .map((entry) => _line(clinicalLabel(entry.key), entry.value))
            .toList(),
        result: trace.reason,
        technicalRuleId: trace.ruleId,
      );
  }
}

String _result(
  ReasoningTraceEntry trace, {
  required String yes,
  required String no,
  required String unknown,
}) => trace.matched == null
    ? unknown
    : trace.matched!
    ? yes
    : no;

String _line(String label, Object? value, {String suffix = ''}) =>
    '$label: ${value == null ? 'Not provided' : '${factText(value)}$suffix'}';

String _siteText(String site) => switch (site) {
  'femoral_neck' => 'femoral neck',
  'lumbar_spine' => 'lumbar spine',
  _ => site.replaceAll('_', ' '),
};
