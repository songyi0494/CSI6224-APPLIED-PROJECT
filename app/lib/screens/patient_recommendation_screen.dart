import 'package:flutter/material.dart';

import '../models/clinical_result_contract.dart';

class PatientRecommendationScreen extends StatelessWidget {
  const PatientRecommendationScreen({required this.result, super.key});

  final PatientApprovedResult result;

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
                  _section(context, 'Reviewed by Your Clinician', [
                    const Text(
                      'Your clinician has reviewed and approved this result.',
                    ),
                  ]),
                  _section(context, 'Lifestyle Recommendations', [
                    for (final advice in result.lifestyleRecommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(advice),
                      ),
                  ]),
                  _section(context, 'Care Recommendation', [
                    for (final action in result.careRecommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(action.description),
                      ),
                  ]),
                  _section(context, 'Clinician Message', [
                    Text(result.clinicianMessage),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
