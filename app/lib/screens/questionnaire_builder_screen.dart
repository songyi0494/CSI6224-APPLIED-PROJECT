import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/questionnaire.dart';
import '../widgets/empty_state.dart';

class QuestionnaireBuilderScreen extends StatelessWidget {
  const QuestionnaireBuilderScreen({required this.repository, super.key});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaire builder')),
      body: FutureBuilder<List<Questionnaire>>(
        future: repository.fetchQuestionnaires(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final questionnaires = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reusable components',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('Text')),
                          Chip(label: Text('Yes/No')),
                          Chip(label: Text('Number')),
                          Chip(label: Text('Scale')),
                          Chip(label: Text('Choice')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import JSON'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.download),
                        label: const Text('Export JSON'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current questionnaires',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (questionnaires.isEmpty)
                        const EmptyState(
                          message: 'Create the first questionnaire.',
                        )
                      else
                        for (final questionnaire in questionnaires)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(questionnaire.title),
                            subtitle: Text(questionnaire.status.name),
                            children: [
                              for (final question in questionnaire.questions)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.drag_indicator),
                                  title: Text(question.prompt),
                                  subtitle: Text(question.type.name),
                                ),
                            ],
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
