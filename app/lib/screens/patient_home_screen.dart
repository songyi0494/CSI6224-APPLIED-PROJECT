import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../utils/patient_decision_presentation.dart';
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

  Future<void> _withdrawAndEdit(
    BuildContext context,
    ClinicalCase assessment,
    VoidCallback reload,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdraw submission?'),
        content: const Text(
          'Your assessment will return to draft so you can make changes. You will need to submit it again for clinician review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw and edit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.withdrawAssessment(assessment: assessment);
      if (!context.mounted) return;
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your assessment is back in draft. You can edit it now.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AppException
                ? e.message
                : 'This assessment can no longer be edited directly.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Patient Dashboard',
    user: user,
    onSignOut: onSignOut,
    child: AsyncPanel<List<ClinicalCase>>(
      load: repository.fetchClinicalCases,
      builder: (items, reload) {
        final activeAssessment = _activeAssessment(items);
        return Column(
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
                  icon: Icon(
                    activeAssessment == null ? Icons.add : Icons.edit_outlined,
                  ),
                  label: Text(
                    activeAssessment == null
                        ? 'Start assessment'
                        : activeAssessment.canEdit
                        ? 'Continue current assessment'
                        : 'Assessment in progress',
                  ),
                  onPressed:
                      activeAssessment != null && !activeAssessment.canEdit
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PathwayFormScreen(
                                repository: repository,
                                user: user,
                                assessment: activeAssessment,
                              ),
                            ),
                          );
                          reload();
                        },
                ),
                OutlinedButton(onPressed: reload, child: const Text('Refresh')),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'My assessments',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text(
                'No assessments yet. Your assessments will appear here after they are created.',
              ),
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Builder(
                  builder: (context) {
                    final presentation = PatientDecisionPresentation.fromCase(
                      a,
                    );
                    final notes = a.decisionNotes?.trim();
                    return Card(
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
                        if (a.status ==
                            ClinicalCaseStatus.clinicianInputRequired)
                          const Text(
                            'Submitted — waiting for clinician clinical input.',
                          ),
                            if (presentation != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                presentation.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(presentation.description),
                              if (presentation.showRecommendation &&
                                  a.approvedActions.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Reviewed recommendation',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                for (final action in a.approvedActions)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(action.description),
                                  ),
                              ],
                              if (notes != null && notes.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  presentation.messageLabel,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(notes),
                              ],
                              if (a.status == ClinicalCaseStatus.needsMoreInfo)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Please follow the instructions from your clinician before the assessment can be completed.',
                                  ),
                                ),
                              if (a.status ==
                                  ClinicalCaseStatus.followUpArranged)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Please follow the instructions from your clinician for the next step.',
                                  ),
                                ),
                            ],
                        if (presentation == null &&
                            a.decisionNotes != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            a.status == ClinicalCaseStatus.needsMoreInfo
                                ? 'Action needed'
                                : 'Message from your clinician',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(a.decisionNotes!),
                        ],
                            if (a.canEdit &&
                                (presentation == null ||
                                    presentation.allowAssessmentEdit)) ...[
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
                        if (a.canWithdrawSubmission) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _withdrawAndEdit(
                              context,
                              a,
                              reload,
                            ),
                            child: const Text('Withdraw and edit'),
                          ),
                        ],
                            if (presentation?.showRecommendation == true) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Reviewed recommendation'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Your clinician has reviewed your assessment.',
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Recommendation',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      for (final action in a.approvedActions)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(action.description),
                                        ),
                                      if (notes != null &&
                                          notes.isNotEmpty) ...[
                                        Text(
                                          presentation!.messageLabel,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        Text(notes),
                                      ],
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
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );

  static ClinicalCase? _activeAssessment(List<ClinicalCase> items) {
    for (final item in items) {
      if (_activeStatuses.contains(item.status)) return item;
    }
    return null;
  }

  static const _activeStatuses = {
    ClinicalCaseStatus.draft,
    ClinicalCaseStatus.clinicianInputRequired,
    ClinicalCaseStatus.awaitingReview,
    ClinicalCaseStatus.manualReview,
    ClinicalCaseStatus.needsMoreInfo,
  };
}
