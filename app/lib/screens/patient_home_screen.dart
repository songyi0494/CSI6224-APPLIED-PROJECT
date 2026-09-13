import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';
import 'pathway_form_screen.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({
    required this.user,
    required this.repository,
    required this.onSignOut,
    super.key,
  });
  final AppUser user;
  final AppRepository repository;
  final VoidCallback onSignOut;
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Patient Dashboard',
    user: user,
    onSignOut: onSignOut,
    child: AsyncPanel<List<ClinicalCase>>(
      load: repository.fetchClinicalCases,
      builder: (items, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OsteoCare Pathway',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your health information, assessment status and reviewed recommendations.',
          ),
          if (repository.isMock)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Demo mode — synthetic records. Changes last for this app session.',
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Start assessment'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PathwayFormScreen(repository: repository, user: user),
                    ),
                  );
                  reload();
                },
              ),
              OutlinedButton(onPressed: reload, child: const Text('Refresh')),
            ],
          ),
          const SizedBox(height: 24),
          Text('My assessments', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'No assessments yet. Your assessments will appear here after they are created.',
            ),
          for (final a in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.submittedAt == null
                            ? 'Your assessment'
                            : 'Submitted ${formatDate(a.submittedAt!)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Chip(label: Text(a.status.label)),
                      if (a.status == ClinicalCaseStatus.manualReview)
                        const Text(
                          'A clinician will review your health and treatment information before the next step.',
                        ),
                      if (a.decisionNotes != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          a.status == ClinicalCaseStatus.needsMoreInfo
                              ? 'Action needed'
                              : 'Message from your clinician',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(a.decisionNotes!),
                      ],
                      if (a.canEdit) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => PathwayFormScreen(
                                  repository: repository,
                                  user: user,
                                  assessment: a,
                                ),
                              ),
                            );
                            reload();
                          },
                          child: Text(
                            a.status == ClinicalCaseStatus.needsMoreInfo
                                ? 'Provide more information'
                                : 'Continue assessment',
                          ),
                        ),
                      ],
                      if (a.status == ClinicalCaseStatus.approved) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Your assessment has been reviewed. Your clinician has approved the recommendation.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Approved recommendation'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final action in a.approvedActions)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Text(action.description),
                                      ),
                                    if (a.decisionNotes != null)
                                      Text(a.decisionNotes!),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text('View recommendation'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
