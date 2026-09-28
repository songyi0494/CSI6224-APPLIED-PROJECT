import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../widgets/async_panel.dart';
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
    final assessment = await repository.fetchClinicalCase(caseId);
    return _ClinicianCaseData(
      assessment: assessment,
      questionnaire: await repository.fetchQuestionnaireForm(),
      response: await repository.fetchQuestionnaireResponse(
        patientId: assessment.patientId,
      ),
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

  Widget _answerRow(
    BuildContext context,
    String label,
    Object? value, {
    String provenance = 'Patient reported',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(value?.toString() ?? 'Not provided'),
        Text(provenance, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  String _actionLabel(ClinicalCase assessment) {
    if (assessment.needsClinicianInput) {
      return assessment.clinicianInput == null
          ? 'Start Pathway Assessment'
          : 'Continue Pathway Assessment';
    }
    if (assessment.canReview) return 'Review Result';
    return 'View Result';
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
              final questions = {
                for (final question
                    in data.questionnaire?.questions ??
                        const <QuestionnaireQuestion>[])
                  question.fieldKey: question,
              };
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
                  _section(context, 'Assessment Status', [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(label: Text(assessment.status.label)),
                    ),
                    const Text(
                      'Patient-reported information remains separate from clinician-confirmed facts.',
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _section(context, 'Patient-Reported Questionnaire', [
                    if (response == null)
                      const Text(
                        'No questionnaire response has been submitted.',
                      )
                    else
                      for (final entry in response.answers.entries)
                        if (!const {
                          'smoking',
                          'alcohol',
                          'dietaryDairyServings',
                        }.contains(entry.key))
                          _answerRow(
                            context,
                            questions[entry.key]?.questionText ?? entry.key,
                            entry.value,
                          ),
                  ]),
                  const SizedBox(height: 12),
                  _section(context, 'Lifestyle Information', [
                    if (response == null)
                      const Text(
                        'No patient-reported lifestyle data available.',
                      )
                    else
                      for (final key in const [
                        'smoking',
                        'alcohol',
                        'dietaryDairyServings',
                      ])
                        if (response.answers.containsKey(key))
                          _answerRow(
                            context,
                            questions[key]?.questionText ?? key,
                            response.answers[key],
                          ),
                  ]),
                  const SizedBox(height: 12),
                  _section(context, 'Relevant Clinical Information', [
                    for (final entry in assessment.input.toFacts().entries)
                      if (_patientClinicalKeys.contains(entry.key))
                        _answerRow(
                          context,
                          clinicalLabel(entry.key),
                          factText(entry.value),
                          provenance:
                              'Patient submitted — not clinician confirmed',
                        ),
                  ]),
                  const SizedBox(height: 12),
                  _section(context, 'Pathway Status', [
                    Text(
                      assessment.pathway == ClinicalPathway.pathway1
                          ? 'Pathway 1 — Treatment naïve'
                          : assessment.pathway == ClinicalPathway.pathway2
                          ? 'Pathway 2 — Previous osteoporosis treatment'
                          : 'Treatment history needs review',
                    ),
                    if (assessment.routingReason != null)
                      Text(assessment.routingReason!),
                  ]),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () async {
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
                      },
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

  static const _patientClinicalKeys = {
    'osteoporosisTreatmentStatus',
    'age',
    'sex',
    'postmenopausal',
    'minimalTraumaFracture',
    'fractureSite',
    'liveInResidentialCare',
  };
}

class _ClinicianCaseData {
  const _ClinicianCaseData({
    required this.assessment,
    this.questionnaire,
    this.response,
  });

  final ClinicalCase assessment;
  final QuestionnaireForm? questionnaire;
  final QuestionnaireResponse? response;
}
