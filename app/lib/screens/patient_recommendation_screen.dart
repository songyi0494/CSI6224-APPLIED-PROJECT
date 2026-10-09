import '../widgets/global_sign_out.dart';
import '../widgets/pathway_action_view.dart';

import 'package:flutter/material.dart';

import '../models/clinical_result_contract.dart';

class PatientRecommendationScreen extends StatelessWidget {
  const PatientRecommendationScreen({
    required this.result,
    this.onSignOut,
    super.key,
  });

  final PatientApprovedResult result;
  final VoidCallback? onSignOut;

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
      appBar: AppBar(
        title: const Text('Your Care Plan'),
        actions: [
          if (onSignOut != null) GlobalSignOutButton(onPressed: onSignOut),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('Reviewed and approved by your clinician.'),
                  ),
                  _section(context, 'Your Bone Health Advice', [
                    for (final advice in result.lifestyleRecommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(advice),
                      ),
                  ]),
                  _section(context, 'Treatment Options', [
                    for (final action in result.careRecommendations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PathwayActionView(
                          action: action,
                          patientSection: PatientActionSection.treatment,
                        ),
                      ),
                  ]),
                  _section(context, 'Follow-up', [
                    if (!result.careRecommendations.any(
                      (action) => PathwayActionView.hasContent(
                        action.raw,
                        PatientActionSection.followUp,
                      ),
                    ))
                      const Text(
                        'Follow-up has not been specified in this care plan.',
                      ),
                    for (final action in result.careRecommendations)
                      PathwayActionView(
                        action: action,
                        patientSection: PatientActionSection.followUp,
                      ),
                  ]),
                  _section(context, 'Message from your clinician', [
                    Text(result.clinicianMessage),
                  ]),
                  FilledButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    child: const Text('Return to dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
