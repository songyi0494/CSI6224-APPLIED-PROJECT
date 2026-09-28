import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../utils/clinical_labels.dart';
import '../utils/clinical_trace_presentation.dart';
import '../widgets/async_panel.dart';
import 'pathway_question_screen.dart';

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

  Widget _clinicalInputCard(
    ClinicalCase assessment,
    VoidCallback reload,
  ) => _card('Pathway Assessment', [
    const Text(
      'Confirm one clinical fact at a time. Patient-reported answers are not promoted to clinician-confirmed facts.',
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      onPressed: _saving
          ? null
          : () => _openPathwayQuestions(assessment, reload),
      icon: const Icon(Icons.play_arrow),
      label: Text(
        assessment.clinicianFacts.isEmpty
            ? 'Start guided pathway questions'
            : 'Continue guided pathway questions',
      ),
    ),
  ]);

  Future<void> _openPathwayQuestions(
    ClinicalCase assessment,
    VoidCallback reload,
  ) async {
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => PathwayQuestionScreen(
          caseId: assessment.id,
          repository: widget.repository,
        ),
      ),
    );
    if (completed == true && mounted) {
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pathway evaluation completed.')),
      );
    }
  }

  Widget _decisionChoice({
    required ClinicalCaseStatus decision,
    required String label,
    required IconData icon,
  }) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: _decision == decision,
    onSelected: _saving
        ? null
        : (selected) => setState(() {
            _decision = selected ? decision : null;
            _error = null;
          }),
  );

  Widget _traceTile(ClinicalCase assessment, int index) {
    final trace = assessment.evaluation!.trace[index];
    final item = clinicalTracePresentation(
      trace,
      clinicianInput: assessment.clinicianInput,
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: index == assessment.evaluation!.trace.length - 1 ? 0 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final detail in item.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(detail),
            ),
          const SizedBox(height: 4),
          Text('Result: ${item.result}'),
          if (item.implication != null) Text('Next: ${item.implication}'),
          Text(
            'Technical rule: ${item.technicalRuleId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _decisionCard(
    ClinicalCase assessment,
    VoidCallback reload,
  ) => _card('Clinician Decision', [
    const Text('Select a decision'),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (assessment.evaluation?.canApprove == true)
          _decisionChoice(
            decision: ClinicalCaseStatus.approved,
            label: 'Approve',
            icon: Icons.check_circle_outline,
          ),
        _decisionChoice(
          decision: ClinicalCaseStatus.withheld,
          label: 'Withhold',
          icon: Icons.block_outlined,
        ),
        _decisionChoice(
          decision: ClinicalCaseStatus.needsMoreInfo,
          label: 'Request more information',
          icon: Icons.help_outline,
        ),
        _decisionChoice(
          decision: ClinicalCaseStatus.followUpArranged,
          label: 'Arrange follow-up',
          icon: Icons.event_outlined,
        ),
      ],
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
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    const SizedBox(height: 16),
    Wrap(
      spacing: 12,
      children: [
        FilledButton(
          onPressed: _saving ? null : () => _save(assessment, reload),
          child: Text(_saving ? 'Saving...' : 'Save decision'),
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
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Clinical assessment result')),
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
                  _card('Assessment Result', [
                    Text(a.patientName),
                    Text('Assessment revision ${a.revision}'),
                    Text(a.status.label),
                    if (a.submittedAt != null)
                      Text('Submitted ${formatDate(a.submittedAt!)}'),
                  ]),
                  _card('Pathway Result', [
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
                  ]),
                  _card('Patient-submitted information', [
                    for (final entry in a.input.toFacts().entries)
                      if (_patientDisplayFactKeys.contains(entry.key))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                          ),
                        ),
                  ]),
                  if (a.clinicianFacts.isNotEmpty)
                    _card('Clinician-entered facts', [
                      for (final entry in a.clinicianFacts.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                          ),
                        ),
                    ]),
                  if (a.needsClinicianInput) _clinicalInputCard(a, reload),
                  _card('Recommended Action', [
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
                  if (a.canReview) _decisionCard(a, reload),
                  if (evaluation != null) ...[
                    Card(
                      child: ExpansionTile(
                        title: const Text('Why This Result'),
                        subtitle: const Text(
                          'Structural traversal returned by the live rule engine',
                        ),
                        childrenPadding: const EdgeInsets.all(20),
                        children: [
                          for (var i = 0; i < evaluation.trace.length; i++)
                            _traceTile(a, i),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                  _card('Lifestyle Recommendations', [
                    const Text(
                      'No personalised lifestyle rule output is available from the current target evaluator.',
                    ),
                  ]),
                  _card('Common Advice', [
                    const Text(
                      'General bone-health topics for discussion include nutrition, safe physical activity and falls prevention. This is common advice, not a personalised rule output.',
                    ),
                  ]),
                  if (a.decisionNotes != null)
                    _card('Recorded decision', [
                      Text(a.decisionNotes!),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Return to Work Queue'),
                        ),
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

  static const _patientDisplayFactKeys = {
    'osteoporosisTreatmentStatus',
    'age',
    'sex',
    'postmenopausal',
    'minimalTraumaFracture',
    'fractureSite',
    'liveInResidentialCare',
  };
}
