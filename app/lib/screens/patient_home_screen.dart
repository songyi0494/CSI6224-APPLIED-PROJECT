import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/questionnaire.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/empty_state.dart';

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
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Patient home',
      user: user,
      onSignOut: onSignOut,
      child: FutureBuilder(
        future: Future.wait([
          repository.fetchQuestionnaires(),
          repository.fetchClinicalCases(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final questionnaires = snapshot.data![0] as List<Questionnaire>;
          final cases = snapshot.data![1] as List<ClinicalCase>;
          final approvedCases = cases
              .where((item) => item.status == ClinicalCaseStatus.approved)
              .toList();
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final children = [
                _QuestionnairePanel(questionnaires: questionnaires),
                _RecommendationPanel(approvedCases: approvedCases),
              ];
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children
                      .map(
                        (child) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: child,
                          ),
                        ),
                      )
                      .toList(),
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
}

class _QuestionnairePanel extends StatelessWidget {
  const _QuestionnairePanel({required this.questionnaires});

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
              'Published questionnaires',
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
                    onPressed: () {},
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
  const _RecommendationPanel({required this.approvedCases});

  final List<ClinicalCase> approvedCases;

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
            if (approvedCases.isEmpty)
              const EmptyState(
                message: 'Recommendations appear here after clinician review.',
              )
            else
              for (final clinicalCase in approvedCases)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(clinicalCase.patientName),
                  subtitle: const Text(
                    'Clinician-approved recommendation available',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
