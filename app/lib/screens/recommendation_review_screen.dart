import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../widgets/async_panel.dart';

class RecommendationReviewScreen extends StatefulWidget {
  const RecommendationReviewScreen({
    required this.caseId,
    required this.repository,
    super.key,
  });
  final String caseId;
  final AppRepository repository;
  @override
  State<RecommendationReviewScreen> createState() =>
      _RecommendationReviewScreenState();
}

class _RecommendationReviewScreenState
    extends State<RecommendationReviewScreen> {
  final _notes = TextEditingController();
  ClinicalCaseStatus? _decision;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(ClinicalCase a, VoidCallback reload) async {
    if (_decision == null || _notes.text.trim().isEmpty) {
      setState(() => _error = 'Choose a decision and enter clinical notes.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordClinicianDecision(
        assessment: a,
        decision: _decision!,
        notes: _notes.text.trim(),
      );
      if (mounted) {
        _notes.clear();
        _decision = null;
        reload();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Decision saved.')));
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Your decision could not be saved. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(String title, List<Widget> content) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...content,
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review assessment')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: AsyncPanel<ClinicalCase>(
            load: () => widget.repository.fetchClinicalCase(widget.caseId),
            builder: (a, reload) {
              final evaluation = a.evaluation;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card('Patient details', [
                    Text(a.patientName),
                    Text('Assessment revision ${a.revision}'),
                    Text(a.status.label),
                    if (a.submittedAt != null)
                      Text('Submitted ${formatDate(a.submittedAt!)}'),
                  ]),
                  _card('Selected pathway', [
                    Text(
                      a.pathway == ClinicalPathway.pathway1
                          ? 'Pathway 1 — Treatment naïve'
                          : a.pathway == ClinicalPathway.pathway2
                          ? 'Pathway 2 — Previous osteoporosis treatment'
                          : 'Treatment history needs review',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.routingReason ??
                          'More treatment information is needed.',
                    ),
                    if (a.pathway == ClinicalPathway.pathway2)
                      const Text(
                        'Pathway 2 integration is not yet available. A manual clinical review is required.',
                      ),
                  ]),
                  _card('Clinical input', [
                    for (final entry in a.input.toFacts().entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                        ),
                      ),
                  ]),
                  _card('System recommendation', [
                    if (evaluation == null || evaluation.actions.isEmpty)
                      const Text(
                        'No recommendation is available for approval.',
                      ),
                    if (evaluation != null)
                      for (final action in evaluation.actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(action.description),
                        ),
                  ]),
                  if (evaluation != null) ...[
                    _card('Why this recommendation was generated', [
                      Text('Rule version: ${evaluation.ruleVersion}'),
                      for (final t in evaluation.trace)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            t.matched == null
                                ? Icons.help_outline
                                : t.matched!
                                ? Icons.check_circle_outline
                                : Icons.remove_circle_outline,
                          ),
                          title: Text(t.reason),
                          subtitle: Text(t.ruleId),
                        ),
                    ]),
                    if (evaluation.missingInputs.isNotEmpty)
                      _card('Information needed', [
                        for (final field in evaluation.missingInputs)
                          Text(
                            '${clinicalLabel(field)} has not been confirmed.',
                          ),
                      ]),
                    if (evaluation.warnings.isNotEmpty)
                      _card('Review notes', [
                        for (final warning in evaluation.warnings)
                          Text(warning),
                      ]),
                  ],
                  if (a.decisionNotes != null)
                    _card('Recorded decision', [Text(a.decisionNotes!)]),
                  if (a.canReview)
                    _card('Clinician decision', [
                      DropdownButtonFormField<ClinicalCaseStatus>(
                        key: ValueKey(a.updatedAt),
                        initialValue: _decision,
                        decoration: const InputDecoration(
                          labelText: 'Decision',
                        ),
                        items: [
                          if (evaluation?.canApprove == true)
                            const DropdownMenuItem(
                              value: ClinicalCaseStatus.approved,
                              child: Text('Approve'),
                            ),
                          const DropdownMenuItem(
                            value: ClinicalCaseStatus.withheld,
                            child: Text('Withhold'),
                          ),
                          const DropdownMenuItem(
                            value: ClinicalCaseStatus.needsMoreInfo,
                            child: Text('Request more information'),
                          ),
                          const DropdownMenuItem(
                            value: ClinicalCaseStatus.followUpArranged,
                            child: Text('Arrange follow-up'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _decision = v),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _notes,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Clinical notes',
                          helperText:
                              'These notes will be shown to the patient. Include the request or follow-up details.',
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _saving ? null : () => _save(a, reload),
                            child: Text(
                              _saving ? 'Saving...' : 'Save decision',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _decision = null;
                                      _error = null;
                                    });
                                    reload();
                                  },
                            child: const Text('Reload assessment'),
                          ),
                        ],
                      ),
                    ]),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
