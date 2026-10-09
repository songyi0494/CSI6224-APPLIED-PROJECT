import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:csi6224_patient_feedback/models/patient_questionnaire_catalog.dart';
import 'final_ui_evidence_test.dart' show UiEvidenceRepository;

const patient = AppUser(
  id: 'synthetic-patient',
  displayName: 'Alex Example',
  email: 'synthetic@example.test',
  role: UserRole.patient,
  sexAtBirth: 'female',
);

class PolishRepository extends UiEvidenceRepository {
  PolishRepository({this.approved = true, this.node, String fixture = 'p1'})
    : super(fixture);
  bool approved;
  String? node;
  String notes = 'Please discuss these options with your GP.';
  final answers = <String, Object>{};
  int signOuts = 0;
  @override
  Future<QuestionnaireForm> fetchQuestionnaireForm() async =>
      buildMaturePatientForm(const []);
  @override
  Future<void> signOut() async {
    signOuts++;
  }

  @override
  Future<ClinicalCase> fetchClinicalCase(String id) async {
    final c = await super.fetchClinicalCase(id);
    return ClinicalCase(
      id: c.id,
      patientId: c.patientId,
      patientName: c.patientName,
      input: c.input,
      status: approved ? ClinicalCaseStatus.approved : c.status,
      revision: c.revision,
      updatedAt: c.updatedAt,
      evaluation: c.evaluation,
      patientSexAtBirth: c.patientSexAtBirth,
      pathway: c.pathway,
      clinicianFacts: node == null ? c.clinicianFacts : answers,
      decisionNotes: approved ? notes : null,
    );
  }

  @override
  Future<List<PatientApprovedResult>> fetchPatientApprovedResults() async =>
      approved ? [await result()] : [];
  Future<PatientApprovedResult> result() async {
    final c = await super.fetchClinicalCase('evidence-case');
    final review = await getClinicalCaseResultsReview(c.id);
    return PatientApprovedResult(
      caseId: c.id,
      reviewedAt: c.updatedAt,
      lifestyleRecommendations: review!.commonAdvice,
      careRecommendations: c.evaluation!.actions,
      clinicianMessage: notes,
    );
  }

  @override
  Future<void> recordClinicianDecision({
    required ClinicalCase assessment,
    required ClinicalCaseStatus decision,
    required String notes,
    ClinicalResultsReview? resultsReview,
  }) async {
    approved = decision == ClinicalCaseStatus.approved;
    this.notes = notes;
  }

  @override
  Future<void> savePathwayAnswer({
    required String caseId,
    required String fieldKey,
    required Object value,
  }) async {
    answers[fieldKey] = value;
  }

  @override
  Future<LivePathwayResult> evaluatePathway({required String caseId}) async {
    final keys = switch (node) {
      'MINIMAL_TRAUMA_FRACTURE' => ['minimalTraumaFracture'],
      'FRACTURE_SITE_ELIGIBLE' => ['fractureSite'],
      'ADHERENCE_CONCERN' => ['adherenceConcern'],
      _ => ['eGFR'],
    };
    return PathwayQuestionStep(
      pathwayId: 'PATHWAY1',
      nodeId: node ?? 'RENAL_DYSFUNCTION',
      question: switch (node) {
        'MINIMAL_TRAUMA_FRACTURE' =>
          'Did the fracture occur after a fall from standing height or less?',
        'FRACTURE_SITE_ELIGIBLE' => 'Where was the fracture?',
        'ADHERENCE_CONCERN' =>
          'Is the patient able to adhere to the treatment plan?',
        _ => "Is the patient's eGFR 30 mL/min or higher?",
      },
      requiredFacts: keys,
      trace: const [],
    );
  }
}

Future<void> mountPolish(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
