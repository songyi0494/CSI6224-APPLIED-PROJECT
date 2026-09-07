import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/questionnaire.dart';
import '../widgets/app_scaffold.dart';
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
  final VoidCallback onOpenQuestionnaireBuilder;
  final ValueChanged<String> onOpenPathwayCase;
  final VoidCallback onCreatePathwayCase;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Clinician dashboard',
      user: user,
      onSignOut: onSignOut,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onCreatePathwayCase,
        icon: const Icon(Icons.add),
        label: const Text('New pathway case'),
      ),
      child: FutureBuilder(
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    label: 'Responses',
                    value: responses.length.toString(),
                    icon: Icons.inbox_outlined,
                  ),
                  _MetricCard(
                    label: 'Clinical cases',
                    value: cases.length.toString(),
                    icon: Icons.folder_shared_outlined,
                  ),
                  _MetricCard(
                    label: 'Questionnaires',
                    value: questionnaires.length.toString(),
                    icon: Icons.dynamic_form_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Questionnaire management',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: onOpenQuestionnaireBuilder,
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Builder'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final item in questionnaires)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.assignment_outlined),
                          title: Text(item.title),
                          subtitle: Text(item.status.name),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
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
                      for (final clinicalCase in cases)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.route_outlined),
                          title: Text(clinicalCase.patientName),
                          subtitle: Text(clinicalCase.pathway.name),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusChip(label: clinicalCase.status.name),
                              IconButton(
                                tooltip: 'Open case',
                                onPressed: () =>
                                    onOpenPathwayCase(clinicalCase.id),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
