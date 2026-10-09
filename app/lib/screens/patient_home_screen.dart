import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_result_contract.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';
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

  Future<_QuestionnaireHomeData> _loadQuestionnaire() async =>
      _QuestionnaireHomeData(
        form: await repository.fetchQuestionnaireForm(),
        response: await repository.fetchQuestionnaireResponse(
          patientId: user.id,
        ),
      );

  Widget _questionnaireCard(
    BuildContext context,
    VoidCallback reload, {
    required bool hasApprovedCarePlan,
  }) {
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
              subtitle: const Text('Please try again later.'),
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
                        'Bone Health Questionnaire',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(
                      label: Text(
                        submitted
                            ? 'Completed'
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
                      ? hasApprovedCarePlan
                            ? 'Your questionnaire has been reviewed.'
                            : 'Your responses are waiting for clinician review.'
                      : hasDraft
                      ? 'Your saved responses are ready to resume and submit.'
                      : 'Complete your bone health questionnaire before clinical review.',
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
                                      onSignOut: onSignOut,
                                      profileSexAtBirth: user.sexAtBirth,
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
                                  onSignOut: onSignOut,
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
    child: AsyncPanel<List<PatientApprovedResult>>(
      load: repository.fetchPatientApprovedResults,
      builder: (items, reload) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your Bone Health Care',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Complete your questionnaire and view care plans approved by your clinician.',
            ),
            if (repository.isMock)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Demo mode — synthetic records. Changes last for this app session.',
                ),
              ),
            _questionnaireCard(
              context,
              reload,
              hasApprovedCarePlan: items.isNotEmpty,
            ),
            const SizedBox(height: 24),
            Text(
              'My Assessments',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (items.isEmpty) const Text('No assessments yet.'),
            for (final result in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Care plan ready',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Reviewed ${formatDate(result.reviewedAt)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your clinician has reviewed and approved your care plan.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PatientRecommendationScreen(
                                result: result,
                                onSignOut: onSignOut,
                              ),
                            ),
                          ),
                          child: const Text('View care plan'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _QuestionnaireHomeData {
  const _QuestionnaireHomeData({required this.form, required this.response});

  final QuestionnaireForm form;
  final QuestionnaireResponse? response;
}
