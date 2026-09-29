import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_result_contract.dart';
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
    return _ClinicianCaseData(
      assessment: assessment,
      response: await repository.fetchQuestionnaireResponse(
        patientId: assessment.patientId,
      ),
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
              final response = data.response;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section(context, 'Patient Overview', [
                    Text(
                      assessment.patientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Assessment revision ${assessment.revision}'),
                    if (assessment.submittedAt != null)
                      Text('Submitted ${formatDate(assessment.submittedAt!)}'),
                  ]),
                  const SizedBox(height: 12),
                  _section(context, 'Patient-Reported Questionnaire', [
                    _answerRow(
                      context,
                      'Sex recorded at birth',
                      sexAtBirthText(assessment.patientSexAtBirth),
                    ),
                    for (final item in _patientQuestionnaireItems)
                      _answerRow(
                        context,
                        item.label,
                        _questionnaireValue(assessment, response, item.key),
                      ),
                    _answerRow(
                      context,
                      'Age',
                      data.patientSummary?.age ?? 'Unavailable',
                    ),
                  ]),
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

  static const _patientQuestionnaireItems = <({String key, String label})>[
    (key: 'postmenopausal', label: 'Postmenopausal status'),
    (key: 'dietaryDairyServings', label: 'Dietary dairy servings'),
    (key: 'smoking', label: 'Smoking'),
    (key: 'alcohol', label: 'Alcohol'),
  ];
}

class _ClinicianCaseData {
  const _ClinicianCaseData({
    required this.assessment,
    this.response,
    this.investigations,
    this.investigationsError,
    this.patientSummary,
  });

  final ClinicalCase assessment;
  final QuestionnaireResponse? response;
  final CaseInvestigations? investigations;
  final String? investigationsError;
  final ClinicalCasePatientSummary? patientSummary;
}
