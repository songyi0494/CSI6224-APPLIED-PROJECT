import 'package:flutter/material.dart';

import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';

class QuestionnaireSubmittedScreen extends StatelessWidget {
  const QuestionnaireSubmittedScreen({required this.response, super.key});

  final QuestionnaireResponse response;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Questionnaire submitted')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Questionnaire submitted',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your responses have been sent for clinician review.',
                    textAlign: TextAlign.center,
                  ),
                  if (response.submittedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Submitted ${formatDate(response.submittedAt!)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return to dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
