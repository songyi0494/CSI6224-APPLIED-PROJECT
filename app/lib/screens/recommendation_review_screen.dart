import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';
import '../utils/display_labels.dart';

class RecommendationReviewScreen extends StatefulWidget {
  const RecommendationReviewScreen({
    required this.clinicalCase,
    required this.evaluation,
    required this.repository,
    super.key,
  });

  final ClinicalCase clinicalCase;
  final PathwayEvaluation evaluation;
  final AppRepository repository;

  @override
  State<RecommendationReviewScreen> createState() =>
      _RecommendationReviewScreenState();
}

class _RecommendationReviewScreenState
    extends State<RecommendationReviewScreen> {
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final evaluation = widget.evaluation;
    return Scaffold(
      appBar: AppBar(title: const Text('Recommendation review')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.clinicalCase.patientName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recommendation status: '
                    '${pathwayDecisionLabel(evaluation.decision)}',
                  ),
                  if (evaluation.warning != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      evaluation.warning!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _RecommendationCard(evaluation: evaluation),
          const SizedBox(height: 16),
          if (evaluation.missingInputs.isNotEmpty) ...[
            _TextListCard(
              title: 'Missing inputs',
              icon: Icons.error_outline,
              items: evaluation.missingInputs,
            ),
            const SizedBox(height: 16),
          ],
          if (evaluation.unsafeInputs.isNotEmpty) ...[
            _TextListCard(
              title: 'Unsafe or cautionary inputs',
              icon: Icons.warning_amber_outlined,
              items: evaluation.unsafeInputs,
            ),
            const SizedBox(height: 16),
          ],
          _TraceCard(trace: evaluation.trace),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clinician decision',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Clinical notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (evaluation.missingInputs.isNotEmpty) ...[
                    const Text(
                      'Complete the missing information before approving this recommendation.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _saving || evaluation.missingInputs.isNotEmpty
                                ? null
                                : () => _record(ClinicalCaseStatus.approved),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Approve'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _record(ClinicalCaseStatus.withheld),
                        icon: const Icon(Icons.block),
                        label: const Text('Withhold'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _record(ClinicalCaseStatus.needsMoreInfo),
                        icon: const Icon(Icons.search),
                        label: const Text('Request more information'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () =>
                                _record(ClinicalCaseStatus.followUpArranged),
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Arrange follow-up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _record(ClinicalCaseStatus decision) async {
    setState(() => _saving = true);
    await widget.repository.recordClinicianDecision(
      caseId: widget.clinicalCase.id,
      decision: decision,
      notes: _notesController.text.trim(),
      recommendationSummary: _recommendationSummary(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Decision recorded: ${clinicalCaseStatusLabel(decision)}',
        ),
      ),
    );
  }

  String _recommendationSummary() {
    if (widget.evaluation.actions.isEmpty) {
      return 'No recommendation generated; clinician review recorded.';
    }
    return widget.evaluation.actions
        .map((action) => action.description)
        .join(' ');
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.evaluation});

  final PathwayEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommendation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (evaluation.actions.isEmpty)
              const Text('No recommendation was generated.')
            else
              for (final action in evaluation.actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(action.description),
                  subtitle: Text(pathwayActionTypeLabel(action.type)),
                ),
          ],
        ),
      ),
    );
  }
}

class _TextListCard extends StatelessWidget {
  const _TextListCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _TraceCard extends StatelessWidget {
  const _TraceCard({required this.trace});

  final List<String> trace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Triggered rules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in trace)
                  Chip(
                    avatar: const Icon(Icons.account_tree_outlined, size: 18),
                    label: Text(item),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
