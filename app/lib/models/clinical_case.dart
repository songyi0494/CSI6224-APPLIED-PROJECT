import 'clinical_input.dart';
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
    this.decisionNotes,
    this.approvedActions = const [],
  });
  final String id, patientId, patientName;
  final ClinicalInput input;
  final ClinicalCaseStatus status;
  final int revision;
  final DateTime updatedAt;
  final DateTime? submittedAt;
  final ClinicalPathway? pathway;
  final String? routingReason, evaluationId, decisionNotes;
  final PathwayEvaluation? evaluation;
  final List<PathwayAction> approvedActions;
  bool get canEdit =>
      status == ClinicalCaseStatus.draft ||
      status == ClinicalCaseStatus.needsMoreInfo;
  bool get canReview =>
      status == ClinicalCaseStatus.awaitingReview ||
      status == ClinicalCaseStatus.manualReview;
  factory ClinicalCase.fromJson(Map<String, dynamic> j) => ClinicalCase(
    id: j['id'] as String,
    patientId: j['patient_id'] as String,
    patientName: j['patient_name'] as String,
    input: ClinicalInput.fromFacts(
      Map<String, dynamic>.from(j['facts'] as Map),
    ),
    status: ClinicalCaseStatus.values.firstWhere((s) => s.value == j['status']),
    revision: j['revision'] as int,
    updatedAt: DateTime.parse(j['updated_at'] as String),
    submittedAt: DateTime.tryParse(j['submitted_at']?.toString() ?? ''),
    pathway: j['pathway'] == 'PATHWAY1'
        ? ClinicalPathway.pathway1
        : j['pathway'] == 'PATHWAY2'
        ? ClinicalPathway.pathway2
        : null,
    routingReason: j['routing_reason'] as String?,
    evaluationId: j['evaluation_id'] as String?,
    decisionNotes: j['decision_notes'] as String?,
    evaluation: j['evaluation'] == null
        ? null
        : PathwayEvaluation.fromJson(
            Map<String, dynamic>.from(j['evaluation'] as Map),
          ),
    approvedActions: (j['approved_actions'] as List? ?? [])
        .map((a) => PathwayAction.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList(),
  );
}

enum ClinicalPathway { pathway1, pathway2 }

enum ClinicalCaseStatus {
  draft('draft', 'Draft'),
  awaitingReview('awaiting_review', 'Waiting for clinician review'),
  manualReview('manual_review', 'Further review needed'),
  approved('approved', 'Reviewed and approved'),
  withheld('withheld', 'Recommendation withheld'),
  needsMoreInfo('needs_more_information', 'More information needed'),
  followUpArranged('follow_up_required', 'Follow-up needed');

  const ClinicalCaseStatus(this.value, this.label);
  final String value, label;
}
