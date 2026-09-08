import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/questionnaire.dart';
import '../utils/display_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';

class ClinicianDashboardScreen extends StatelessWidget {
  const ClinicianDashboardScreen({
    required this.user,
    required this.repository,
    required this.onSignOut,
    required this.onOpenQuestionnaireBuilder,
    required this.onOpenPathwayCase,
    required this.onCreatePathwayCase,
    super.key,
  });

  final AppUser user;
  final AppRepository repository;
  final VoidCallback onSignOut;
  final void Function(String? questionnaireId) onOpenQuestionnaireBuilder;
  final ValueChanged<String> onOpenPathwayCase;
  final VoidCallback onCreatePathwayCase;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Clinician workspace',
      user: user,
      onSignOut: onSignOut,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onCreatePathwayCase,
        icon: const Icon(Icons.add),
        label: const Text('New pathway case'),
      ),
      child: FutureBuilder<List<Object>>(
        future: Future.wait([
          repository.fetchPatientResponses(),
          repository.fetchClinicalCases(),
          repository.fetchQuestionnaires(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final responses = snapshot.data![0] as List<PatientResponse>;
          final cases = snapshot.data![1] as List<ClinicalCase>;
          final questionnaires = snapshot.data![2] as List<Questionnaire>;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResponsesSection(
                responses: responses,
                questionnaires: questionnaires,
              ),
              const SizedBox(height: 16),
              _QuestionnairesSection(
                questionnaires: questionnaires,
                onOpenBuilder: onOpenQuestionnaireBuilder,
              ),
              const SizedBox(height: 16),
              _CasesSection(cases: cases, onOpenCase: onOpenPathwayCase),
            ],
          );
        },
      ),
    );
  }
}

class _ResponsesSection extends StatelessWidget {
  const _ResponsesSection({
    required this.responses,
    required this.questionnaires,
  });

  final List<PatientResponse> responses;
  final List<Questionnaire> questionnaires;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient responses',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (responses.isEmpty)
              const EmptyState(message: 'No patient responses submitted yet.')
            else
              for (final response in responses)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text(response.patientName),
                  subtitle: Text(
                    '${response.questionnaireTitle}\n'
                    'Submitted ${_formatSubmittedAt(response.submittedAt)}',
                  ),
                  children: [
                    for (final entry in response.answers.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_questionPrompt(response, entry.key)),
                        subtitle: Text(_answerLabel(entry.value)),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  String _questionPrompt(PatientResponse response, String questionId) {
    for (final questionnaire in questionnaires) {
      if (questionnaire.id != response.questionnaireId) {
        continue;
      }
      for (final question in questionnaire.questions) {
        if (question.id == questionId) {
          return question.prompt;
        }
      }
    }
    return questionId;
  }

  String _answerLabel(Object? value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'Not answered';
    }
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    return value.toString();
  }

  String _formatSubmittedAt(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'am' : 'pm';
    return '${value.day} ${months[value.month - 1]} ${value.year}, '
        '$hour:$minute $suffix';
  }
}

class _QuestionnairesSection extends StatelessWidget {
  const _QuestionnairesSection({
    required this.questionnaires,
    required this.onOpenBuilder,
  });

  final List<Questionnaire> questionnaires;
  final void Function(String? questionnaireId) onOpenBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Questionnaires',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => onOpenBuilder(null),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Manage'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (questionnaires.isEmpty)
              const EmptyState(message: 'No questionnaires configured.')
            else
              for (final item in questionnaires)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(item.title),
                  subtitle: Text(
                    '${questionnaireStatusLabel(item.status)} - '
                    '${item.questions.length} questions',
                  ),
                  trailing: item.status == QuestionnaireStatus.draft
                      ? TextButton(
                          onPressed: () => onOpenBuilder(item.id),
                          child: const Text('Manage'),
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _CasesSection extends StatelessWidget {
  const _CasesSection({required this.cases, required this.onOpenCase});

  final List<ClinicalCase> cases;
  final ValueChanged<String> onOpenCase;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pathway cases',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (cases.isEmpty)
              const EmptyState(message: 'No pathway cases created yet.')
            else
              for (final clinicalCase in cases)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route_outlined),
                  title: Text(clinicalCase.patientName),
                  subtitle: Text(clinicalPathwayLabel(clinicalCase.pathway)),
                  onTap: () => onOpenCase(clinicalCase.id),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(
                        label: clinicalCaseStatusLabel(clinicalCase.status),
                      ),
                      IconButton(
                        tooltip: 'Open case',
                        onPressed: () => onOpenCase(clinicalCase.id),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
