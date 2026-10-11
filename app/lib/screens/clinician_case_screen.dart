import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_result_contract.dart';
import '../models/patient_questionnaire_catalog.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../widgets/async_panel.dart';
import 'investigations_screen.dart';
import 'pathway_question_screen.dart';
import 'recommendation_review_screen.dart';

class ClinicianCaseScreen extends StatelessWidget {
  const ClinicianCaseScreen({
    required this.caseId,
    required this.repository,
    super.key,
  });

  final String caseId;
  final AppRepository repository;

  Future<_ClinicianCaseData> _load() async {
    var assessment = await repository.fetchClinicalCase(caseId);
    if (assessment.status == ClinicalCaseStatus.clinicianInputRequired) {
      assessment = await repository.claimClinicalCase(caseId);
    }
    CaseInvestigations? investigations;
    ClinicalCasePatientSummary? patientSummary;
    String? investigationsError;
    try {
      investigations = await repository.getCaseInvestigations(caseId);
    } on AppException catch (error) {
      investigationsError = error.message;
    }
    try {
      patientSummary = await repository.getClinicalCasePatientSummary(caseId);
    } on AppException {
      // Age fails closed without exposing DOB or blocking the rest of the case.
    }

    final questionnaireForm = await repository.fetchQuestionnaireForm();

    return _ClinicianCaseData(
      assessment: assessment,
      response: await repository.fetchQuestionnaireResponse(
        patientId: assessment.patientId,
      ),
      questionnaireForm: questionnaireForm,
      investigations: investigations,
      investigationsError: investigationsError,
      patientSummary: patientSummary,
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  String _nextStep(
    ClinicalCase assessment,
    CaseInvestigations? investigations,
  ) {
    if (assessment.needsClinicianInput) {
      return investigations?.canStartPathway == true
          ? 'Review the clinical facts. Then complete the pathway.'
          : 'Complete and confirm the investigations before you start the pathway.';
    }
    if (assessment.status == ClinicalCaseStatus.approved ||
        assessment.status == ClinicalCaseStatus.withheld) {
      return 'View the saved clinician decision.';
    }
    if (assessment.canReview) {
      return 'Review the care result. Then record your decision.';
    }
    return 'Review the case and its current status.';
  }

  Widget _caseSummary(BuildContext context, _ClinicianCaseData data) {
    final assessment = data.assessment;
    final fracture = data.response?.answers['minimalTraumaFracture'];
    final adultFracture = data.response?.answers['adultFractureHistory'];
    return _section(context, 'Clinical Summary', [
      Text(
        assessment.patientName,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text('Age: ${data.patientSummary?.age ?? 'Not available'}'),
      Text(
        'Sex recorded at birth: ${sexAtBirthText(assessment.patientSexAtBirth)}',
      ),
      Text('Case status: ${assessment.status.label}'),
      Text(
        'Patient questionnaire: ${data.response == null
            ? 'Not available'
            : data.response!.status == QuestionnaireResponseStatus.submitted
            ? 'Submitted'
            : 'Draft'}',
      ),
      if (fracture != null)
        Text('Minimal-trauma fracture (patient report): ${factText(fracture)}'),
      if (adultFracture != null)
        Text(
          'Adult fracture history (patient report): ${factText(adultFracture)}',
        ),
      Text(
        'Investigations: ${data.investigations == null ? 'Not available' : _investigationsStatus(data.investigations!)}',
      ),
      const Divider(height: 24),
      Text('Next step', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(_nextStep(assessment, data.investigations)),
    ]);
  }

  Widget _patientReportCard(BuildContext context, _ClinicianCaseData data) {
    final assessment = data.assessment;
    final displayedKeys = {
      'sex',
      for (final question in data.questionnaireForm.orderedQuestions)
        question.productionAnswerKey,
    };
    final historicalLabels = {
      for (final question in maturePatientQuestions)
        question.productionAnswerKey: question.questionText,
    };
    return Card(
      child: ExpansionTile(
        key: const ValueKey('patient-questionnaire-details'),
        title: const Text('Patient-Reported Questionnaire'),
        subtitle: const Text(
          'Open the full report. The clinician must confirm clinical facts.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'These answers are patient-reported.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _answerRow(
            context,
            'Sex recorded at birth',
            data.response?.answers['sex'] ??
                sexAtBirthText(assessment.patientSexAtBirth),
          ),
          for (final question in data.questionnaireForm.orderedQuestions)
            if (question.fieldKey != 'sex')
              _answerRow(
                context,
                question.questionText,
                _questionnaireValue(
                  assessment,
                  data.response,
                  question.productionAnswerKey,
                ),
              ),
          for (final entry
              in (data.response?.answers ?? const <String, Object?>{}).entries)
            if (!displayedKeys.contains(entry.key))
              _answerRow(
                context,
                historicalLabels[entry.key] ?? entry.key,
                entry.value,
              ),
          _answerRow(
            context,
            'Age',
            data.patientSummary?.age ?? 'Not available',
          ),
          if (data.response != null) ...[
            Text('Questionnaire revision ${data.response!.revision}'),
            if (data.response!.submittedAt != null)
              Text(
                'Questionnaire submitted ${formatDate(data.response!.submittedAt!)}',
              ),
          ],
          Text('Assessment revision ${assessment.revision}'),
          if (assessment.submittedAt != null)
            Text('Submitted ${formatDate(assessment.submittedAt!)}'),
        ],
      ),
    );
  }

  Widget _answerRow(BuildContext context, String label, Object? value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(value?.toString() ?? 'Not provided'),
          ],
        ),
      );

  Object? _questionnaireValue(
    ClinicalCase assessment,
    QuestionnaireResponse? response,
    String key,
  ) {
    final answers = response?.answers ?? const <String, Object?>{};
    if (key == 'postmenopausal' &&
        !answers.containsKey(key) &&
        assessment.patientSexAtBirth != 'female') {
      return 'N/A';
    }
    return answers[key];
  }

  String _actionLabel(ClinicalCase assessment) {
    if (assessment.needsClinicianInput) {
      return assessment.clinicianFacts.isEmpty
          ? 'Start Pathway'
          : 'Continue Pathway';
    }
    if (assessment.canReview) return 'Review Result';
    return 'View Result';
  }

  String _investigationsStatus(CaseInvestigations investigations) {
    if (investigations.requiresConfirmation) return 'Requires confirmation';
    if (investigations.canStartPathway) return 'Completed';
    return 'Not completed';
  }

  Future<void> _openInvestigations(
    BuildContext context,
    CaseInvestigations investigations,
    VoidCallback reload,
  ) async {
    final saved = await Navigator.push<CaseInvestigations>(
      context,
      MaterialPageRoute<CaseInvestigations>(
        builder: (_) => InvestigationsScreen(
          repository: repository,
          investigations: investigations,
        ),
      ),
    );
    if (saved != null) reload();
  }

  Future<void> _openPathway(
    BuildContext context,
    ClinicalCase assessment,
    VoidCallback reload,
  ) async {
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => PathwayQuestionScreen(
          caseId: assessment.id,
          repository: repository,
        ),
      ),
    );
    if (completed == true) reload();
  }

  Future<void> _openResult(
    BuildContext context,
    ClinicalCase assessment,
    VoidCallback reload,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecommendationReviewScreen(
          caseId: assessment.id,
          repository: repository,
        ),
      ),
    );
    reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Patient overview')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: AsyncPanel<_ClinicianCaseData>(
            load: _load,
            builder: (data, reload) {
              final assessment = data.assessment;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _caseSummary(context, data),
                  const SizedBox(height: 12),
                  _patientReportCard(context, data),
                  const SizedBox(height: 12),
                  _section(context, 'Investigations', [
                    if (data.investigationsError != null) ...[
                      Text(data.investigationsError!),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ),
                    ] else if (data.investigations != null) ...[
                      Text(
                        _investigationsStatus(data.investigations!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (data.investigations!.vitaminDLevel != null)
                        Text(
                          'Vitamin D: ${data.investigations!.vitaminDLevel} ${CaseInvestigations.vitaminDUnit}',
                        ),
                      if (data.investigations!.ionisedCalcium != null)
                        Text(
                          'Ionised calcium: ${data.investigations!.ionisedCalcium} ${CaseInvestigations.ionisedCalciumUnit}',
                        ),
                      if (data.investigations!.bodyWeightKg != null)
                        Text(
                          'Body weight: ${data.investigations!.bodyWeightKg} ${CaseInvestigations.bodyWeightUnit}',
                        ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _openInvestigations(
                            context,
                            data.investigations!,
                            reload,
                          ),
                          icon: const Icon(Icons.science_outlined),
                          label: Text(
                            data.investigations!.requiresConfirmation
                                ? 'Review investigations'
                                : data.investigations!.hasAnyValue
                                ? 'Edit investigations'
                                : 'Enter investigations',
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  if (assessment.needsClinicianInput &&
                      data.investigations?.canStartPathway != true)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Complete and confirm Investigations before starting the pathway.',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed:
                          assessment.needsClinicianInput &&
                              data.investigations?.canStartPathway != true
                          ? null
                          : () => assessment.needsClinicianInput
                                ? _openPathway(context, assessment, reload)
                                : _openResult(context, assessment, reload),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_actionLabel(assessment)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ClinicianCaseData {
  const _ClinicianCaseData({
    required this.assessment,
    required this.questionnaireForm,
    this.response,
    this.investigations,
    this.investigationsError,
    this.patientSummary,
  });

  final ClinicalCase assessment;
  final QuestionnaireForm questionnaireForm;
  final QuestionnaireResponse? response;
  final CaseInvestigations? investigations;
  final String? investigationsError;
  final ClinicalCasePatientSummary? patientSummary;
}
