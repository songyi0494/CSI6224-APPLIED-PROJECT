import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';
import 'recommendation_review_screen.dart';
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
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Clinician Dashboard',
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Needs review — ${items.where((a) => a.canReview).length}',
                  style: Theme.of(context).textTheme.titleLarge,
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
                children: [
                  const Text('Demo mode — synthetic records only.'),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            QuestionnaireBuilderScreen(repository: repository),
                      ),
                    ),
                    child: const Text('Manage questionnaires'),
                  ),
                ],
              ),
            ),
          if (items.where((a) => a.canReview).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No assessments are waiting for review.'),
            ),
          for (final a in [
            ...items.where((a) => a.canReview),
            ...items.where((a) => !a.canReview),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(a.patientName),
                  subtitle: Text(
                    '${a.submittedAt == null ? '' : formatDate(a.submittedAt!)}\n${a.status.label}\n${a.pathway == ClinicalPathway.pathway1
                        ? 'Pathway 1 — Treatment naïve'
                        : a.pathway == ClinicalPathway.pathway2
                        ? 'Pathway 2 — Previous osteoporosis treatment'
                        : 'Treatment history needs review'}',
                  ),
                  isThreeLine: true,
                  trailing: OutlinedButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RecommendationReviewScreen(
                            caseId: a.id,
                            repository: repository,
                          ),
                        ),
                      );
                      reload();
                    },
                    child: Text(a.canReview ? 'Review' : 'View'),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
