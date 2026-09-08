import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/approved_recommendation.dart';
import '../models/questionnaire.dart';
import '../utils/display_labels.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/empty_state.dart';
import 'questionnaire_response_screen.dart';

class PatientHomeScreen extends StatefulWidget {
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
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Patient home',
      user: widget.user,
      onSignOut: widget.onSignOut,
      child: FutureBuilder<List<Object>>(
        key: ValueKey(_refreshKey),
        future: Future.wait([
          widget.repository.fetchQuestionnaires(),
          widget.repository.fetchApprovedRecommendations(
            patientName: widget.user.displayName,
          ),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final questionnaires = (snapshot.data![0] as List<Questionnaire>)
              .where((item) => item.status == QuestionnaireStatus.published)
              .toList();
          final recommendations =
              snapshot.data![1] as List<ApprovedRecommendation>;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final children = [
                _QuestionnairePanel(
                  questionnaires: questionnaires,
                  onStart: _openQuestionnaire,
                ),
                _RecommendationPanel(recommendations: recommendations),
              ];
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children.first),
                    const SizedBox(width: 16),
                    Expanded(child: children.last),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in children) ...[
                    child,
                    const SizedBox(height: 16),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openQuestionnaire(Questionnaire questionnaire) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionnaireResponseScreen(
          questionnaire: questionnaire,
          repository: widget.repository,
          patientName: widget.user.displayName,
        ),
      ),
    );
    if (mounted) {
      setState(() => _refreshKey++);
    }
  }
}

class _QuestionnairePanel extends StatelessWidget {
  const _QuestionnairePanel({
    required this.questionnaires,
    required this.onStart,
  });

  final List<Questionnaire> questionnaires;
  final ValueChanged<Questionnaire> onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available questionnaires',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (questionnaires.isEmpty)
              const EmptyState(message: 'No questionnaires are available.')
            else
              for (final item in questionnaires)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(item.title),
                  subtitle: Text('${item.questions.length} questions'),
                  trailing: FilledButton(
                    onPressed: () => onStart(item),
                    child: const Text('Start'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationPanel extends StatelessWidget {
  const _RecommendationPanel({required this.recommendations});

  final List<ApprovedRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approved recommendations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (recommendations.isEmpty)
              const EmptyState(
                message: 'Approved recommendations will appear here.',
              )
            else
              for (final recommendation in recommendations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(recommendation.summary),
                  subtitle: Text(
                    '${clinicalPathwayLabel(recommendation.pathway)} approved '
                    '${_formatDate(recommendation.approvedAt)}',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}
