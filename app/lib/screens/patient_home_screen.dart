import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../utils/patient_decision_presentation.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';
import 'pathway_form_screen.dart';
import 'patient_recommendation_screen.dart';
import 'questionnaire_response_screen.dart';
import 'questionnaire_submitted_screen.dart';

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

  Widget _detailSection(
    BuildContext context, {
    required String label,
    required List<Widget> children,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );

  List<Widget> _reviewedDecisionDetails(
    BuildContext context,
    ClinicalCase assessment,
    PatientDecisionPresentation presentation,
  ) {
    final notes = assessment.decisionNotes?.trim();
    return [
      _detailSection(
        context,
        label: 'Outcome',
        children: [
          Text(
            presentation.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(presentation.description),
        ],
      ),
      if (presentation.showRecommendation &&
          assessment.approvedActions.isNotEmpty)
        _detailSection(
          context,
          label: 'Clinician-reviewed recommendation',
          children: [
            for (final action in assessment.approvedActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(action.description),
              ),
          ],
        ),
      if (presentation.actionDescription != null)
        _detailSection(
          context,
          label: 'What you need to do',
          children: [Text(presentation.actionDescription!)],
        ),
      if (presentation.nextStepsDescription != null)
        _detailSection(
          context,
          label: 'Follow-up / next steps',
          children: [Text(presentation.nextStepsDescription!)],
        ),
      if (notes != null && notes.isNotEmpty)
        _detailSection(
          context,
          label: presentation.messageLabel,
          children: [Text(notes)],
        ),
    ];
  }

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

  Future<_QuestionnaireHomeData> _loadQuestionnaire() async =>
      _QuestionnaireHomeData(
        form: await repository.fetchQuestionnaireForm(),
        response: await repository.fetchQuestionnaireResponse(
          patientId: user.id,
        ),
      );

  Widget _questionnaireCard(BuildContext context, VoidCallback reload) {
    return FutureBuilder<_QuestionnaireHomeData>(
      future: _loadQuestionnaire(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Questionnaire unavailable'),
              subtitle: const Text('Refresh the dashboard and try again.'),
            ),
          );
        }
        final data = snapshot.data;
        final response = data?.response;
        final submitted =
            response?.status == QuestionnaireResponseStatus.submitted;
        final hasDraft = response?.status == QuestionnaireResponseStatus.draft;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bone health questionnaire',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(
                      label: Text(
                        submitted
                            ? 'Submitted'
                            : hasDraft
                            ? 'Draft'
                            : 'Not started',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  submitted
                      ? 'Your responses are waiting for clinician review.'
                      : hasDraft
                      ? 'Your saved responses are ready to resume and submit.'
                      : 'Share your bone health, treatment, falls and lifestyle information before clinical review.',
                ),
                if (data?.response?.submittedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Submitted ${formatDate(data!.response!.submittedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!submitted) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: data == null
                        ? null
                        : () async {
                            final response =
                                await Navigator.push<QuestionnaireResponse>(
                                  context,
                                  MaterialPageRoute<QuestionnaireResponse>(
                                    builder: (_) => QuestionnaireResponseScreen(
                                      form: data.form,
                                      repository: repository,
                                      initialAnswers:
                                          data.response?.answers ?? const {},
                                    ),
                                  ),
                                );
                            if (response == null || !context.mounted) return;
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => QuestionnaireSubmittedScreen(
                                  response: response,
                                ),
                              ),
                            );
                            reload();
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      hasDraft ? 'Resume questionnaire' : 'Start questionnaire',
                    ),
                  ),
                ],
                if (data == null) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        );
      },
    );
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
            _questionnaireCard(context, reload),
            const SizedBox(height: 20),
            if (repository.isMock)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    icon: Icon(
                      activeAssessment == null
                          ? Icons.add
                          : Icons.edit_outlined,
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
                  OutlinedButton(
                    onPressed: reload,
                    child: const Text('Refresh'),
                  ),
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
                              const Text('Submitted — waiting for clinician.'),
                            if (presentation != null)
                              ..._reviewedDecisionDetails(
                                context,
                                a,
                                presentation,
                              ),
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
                            if (repository.isMock &&
                                a.canWithdrawSubmission) ...[
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () =>
                                    _withdrawAndEdit(context, a, reload),
                                child: const Text('Withdraw and edit'),
                              ),
                            ],
                            if (presentation?.showRecommendation == true) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => PatientRecommendationScreen(
                                      assessment: a,
                                    ),
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

class _QuestionnaireHomeData {
  const _QuestionnaireHomeData({required this.form, required this.response});

  final QuestionnaireForm form;
  final QuestionnaireResponse? response;
}
