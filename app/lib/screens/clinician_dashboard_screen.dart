import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';
import 'clinician_case_screen.dart';
import 'questionnaire_builder_screen.dart';

class ClinicianDashboardScreen extends StatelessWidget {
  const ClinicianDashboardScreen({
    required this.user,
    required this.repository,
    required this.onSignOut,
    super.key,
  });

  final AppUser user;
  final AppRepository repository;
  final VoidCallback onSignOut;

  Widget _queueSection(
    BuildContext context, {
    required String title,
    required List<ClinicalCase> cases,
    required VoidCallback reload,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Chip(label: Text('${cases.length}')),
        ],
      ),
      const SizedBox(height: 8),
      if (cases.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text('No cases in ${title.toLowerCase()}.'),
          ),
        ),
      for (final assessment in cases)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(assessment.patientName),
              subtitle: Text(
                '${assessment.status.label}'
                '${assessment.submittedAt == null ? '' : '\nSubmitted ${formatDate(assessment.submittedAt!)}'}',
              ),
              isThreeLine: assessment.submittedAt != null,
              trailing: OutlinedButton(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ClinicianCaseScreen(
                        caseId: assessment.id,
                        repository: repository,
                      ),
                    ),
                  );
                  reload();
                },
                child: Text(_actionLabel(assessment)),
              ),
            ),
          ),
        ),
      const SizedBox(height: 18),
    ],
  );

  String _actionLabel(ClinicalCase assessment) {
    if (assessment.canReview) return 'Review';
    if (assessment.needsClinicianInput) return 'Continue';
    return 'View result';
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Clinician Dashboard',
    user: user,
    onSignOut: onSignOut,
    child: AsyncPanel<List<ClinicalCase>>(
      load: repository.fetchClinicalCases,
      builder: (items, reload) {
        final workQueue = items
            .where((item) => item.canReview || item.needsClinicianInput)
            .toList();
        final completed = items
            .where((item) => !item.canReview && !item.needsClinicianInput)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clinical work queue',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Review patient submissions, continue pathway assessments and record decisions.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: reload,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (repository.isMock)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Demo mode — synthetic records only.'),
                    TextButton(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => QuestionnaireBuilderScreen(
                            repository: repository,
                          ),
                        ),
                      ),
                      child: const Text('Manage questionnaires'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _queueSection(
              context,
              title: 'Work Queue',
              cases: workQueue,
              reload: reload,
            ),
            _queueSection(
              context,
              title: 'Completed',
              cases: completed,
              reload: reload,
            ),
          ],
        );
      },
    ),
  );
}
