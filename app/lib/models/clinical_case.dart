import 'clinical_input.dart';
import 'app_user.dart';
import 'pathway1_clinician_input.dart';
import 'pathway_evaluation.dart';

class ClinicalCase {
  const ClinicalCase({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.input,
    required this.status,
    required this.revision,
    required this.updatedAt,
    this.pathway,
    this.routingReason,
    this.submittedAt,
    this.evaluation,
    this.evaluationId,
    this.clinicianInput,
    this.clinicianFacts = const {},
    this.pathwayRevision = 0,
    this.assignedClinicianId,
    this.questionnaireResponseId,
    this.decisionNotes,
    this.approvedActions = const [],
    this.patientSexAtBirth,
  });
  final String id, patientId, patientName;
  final String? patientSexAtBirth;
  final ClinicalInput input;
  final ClinicalCaseStatus status;
  final int revision;
  final DateTime updatedAt;
  final DateTime? submittedAt;
  final ClinicalPathway? pathway;
  final String? routingReason, evaluationId, decisionNotes;
  final PathwayEvaluation? evaluation;
  final Pathway1ClinicianInput? clinicianInput;
  final Map<String, Object?> clinicianFacts;
  final int pathwayRevision;
  final String? assignedClinicianId, questionnaireResponseId;
  final List<PathwayAction> approvedActions;
  bool get canEdit => status == ClinicalCaseStatus.draft;
  bool get needsClinicianInput =>
      status == ClinicalCaseStatus.clinicianInputRequired ||
      status == ClinicalCaseStatus.inProgress;
  bool get canWithdrawSubmission =>
      status == ClinicalCaseStatus.clinicianInputRequired &&
      clinicianInput == null &&
      evaluation == null;
  bool get canReview =>
      status == ClinicalCaseStatus.awaitingReview ||
      status == ClinicalCaseStatus.manualReview ||
      status == ClinicalCaseStatus.evaluated ||
      status == ClinicalCaseStatus.withheld;
  bool get canOpenForClinician => needsClinicianInput || canReview;
  factory ClinicalCase.fromJson(Map<String, dynamic> j) => ClinicalCase(
    id: j['id'] as String,
    patientId: j['patient_id'] as String,
    patientName:
        (j['patient_name'] ??
                (j['patient'] as Map?)?['full_name'] ??
                (j['profiles'] as Map?)?['full_name'] ??
                'Patient')
            .toString(),
    patientSexAtBirth: normalizeSexRecordedAtBirth(
      j['profile_sex_at_birth']?.toString(),
    ),
    input: ClinicalInput.fromFacts(
      Map<String, dynamic>.from(
        (j['facts'] ?? j['patient_facts'] ?? const {}) as Map,
      ),
    ),
    status: ClinicalCaseStatus.values.firstWhere((s) => s.value == j['status']),
    revision: (j['revision'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.parse(j['updated_at'] as String),
    submittedAt: DateTime.tryParse(j['submitted_at']?.toString() ?? ''),
    pathway: j['pathway'] == 'PATHWAY1'
        ? ClinicalPathway.pathway1
        : j['pathway'] == 'PATHWAY2'
        ? ClinicalPathway.pathway2
        : null,
    routingReason: j['routing_reason'] as String?,
    evaluationId: j['evaluation_id'] as String?,
    clinicianInput: _clinicianInputFromJson(j['clinician_facts']),
    clinicianFacts: Map<String, Object?>.from(
      (j['clinician_facts'] as Map?) ?? const {},
    ),
    pathwayRevision: (j['pathway_revision'] as num?)?.toInt() ?? 0,
    assignedClinicianId: j['assigned_clinician_id'] as String?,
    questionnaireResponseId: j['questionnaire_response_id'] as String?,
    decisionNotes: j['decision_notes'] as String?,
    evaluation: (j['evaluation'] ?? j['rule_evaluation']) == null
        ? null
        : PathwayEvaluation.fromJson(
            Map<String, dynamic>.from(
              (j['evaluation'] ?? j['rule_evaluation']) as Map,
            ),
          ),
    approvedActions: (j['approved_actions'] as List? ?? [])
        .map((a) => PathwayAction.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList(),
  );

  static Pathway1ClinicianInput? _clinicianInputFromJson(Object? value) {
    if (value == null) return null;
    final facts = Map<String, dynamic>.from(value as Map);
    if (facts.isEmpty) return null;
    return Pathway1ClinicianInput.fromJson(facts);
  }
}

enum ClinicalPathway { pathway1, pathway2 }

enum ClinicalCaseStatus {
  draft('draft', 'Draft'),
  clinicianInputRequired(
    'clinician_input_required',
    'Submitted — waiting for clinician',
  ),
  inProgress('in_progress', 'Clinician review in progress'),
  evaluated('evaluated', 'Assessment completed'),
  awaitingReview('awaiting_review', 'Waiting for clinician review'),
  manualReview('manual_review', 'Further review needed'),
  approved('approved', 'Reviewed and approved'),
  withheld('withheld', 'Recommendation withheld'),
  needsMoreInfo('needs_more_information', 'More information needed'),
  followUpArranged('follow_up_required', 'Follow-up needed'),
  withdrawn('withdrawn', 'Withdrawn');

  const ClinicalCaseStatus(this.value, this.label);
  final String value, label;
}
