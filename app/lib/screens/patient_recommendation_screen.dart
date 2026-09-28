import 'package:flutter/material.dart';

import '../models/clinical_case.dart';
import '../utils/patient_decision_presentation.dart';

class PatientRecommendationScreen extends StatelessWidget {
  const PatientRecommendationScreen({required this.assessment, super.key});

  final ClinicalCase assessment;

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final presentation = PatientDecisionPresentation.fromCase(assessment)!;
    final notes = assessment.decisionNotes?.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Your Care Recommendation')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section(context, 'Reviewed by your clinician', [
                    Text(
                      presentation.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(presentation.description),
                  ]),
                  if (presentation.showRecommendation)
                    _section(context, 'Care recommendation', [
                      if (assessment.approvedActions.isEmpty)
                        const Text(
                          'No approved treatment action was released.',
                        ),
                      for (final action in assessment.approvedActions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(action.description),
                        ),
                    ]),
                  _section(context, 'Lifestyle recommendations', [
                    const Text(
                      'No personalised lifestyle rule output has been released for this assessment.',
                    ),
                  ]),
                  _section(context, 'Bone health advice', [
                    const Text(
                      'Common advice: discuss nutrition, safe physical activity and falls prevention with your care team. This is general information, not a personalised recommendation.',
                    ),
                  ]),
                  if (presentation.nextStepsDescription != null)
                    _section(context, 'Follow-up', [
                      Text(presentation.nextStepsDescription!),
                    ]),
                  if (presentation.actionDescription != null)
                    _section(context, 'Next steps', [
                      Text(presentation.actionDescription!),
                    ]),
                  if (notes != null && notes.isNotEmpty)
                    _section(context, presentation.messageLabel, [Text(notes)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
