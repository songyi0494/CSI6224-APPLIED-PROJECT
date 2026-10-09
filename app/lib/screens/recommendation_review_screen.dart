import '../widgets/pathway_action_view.dart';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_result_contract.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../utils/clinical_trace_presentation.dart';
import '../utils/recommendation_presentation.dart';
import '../widgets/async_panel.dart';
import '../widgets/global_sign_out.dart';
import 'clinician_case_screen.dart';

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
  final _message = TextEditingController();
  ClinicalCaseStatus? _decision;
  bool _saving = false;
  bool? _hypocalcaemiaDraft;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<_RecommendationReviewData> _load() async {
    final assessment = await widget.repository.fetchClinicalCase(widget.caseId);
    final investigations = await widget.repository.getCaseInvestigations(
      widget.caseId,
    );
    final questionnaire = await widget.repository.fetchQuestionnaireResponse(
      patientId: assessment.patientId,
    );
    final resultsReview = await widget.repository.getClinicalCaseResultsReview(
      widget.caseId,
    );
    return _RecommendationReviewData(
      assessment: assessment,
      investigations: investigations,
      questionnaire: questionnaire,
      resultsReview: resultsReview,
    );
  }

  Future<void> _generateCommonAdvice(
    _RecommendationReviewData data,
    VoidCallback reload,
  ) async {
    final questionnaire = data.questionnaire;
    if (questionnaire == null) {
      setState(() => _error = 'A submitted questionnaire is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.generateClinicalCaseResultsReview(
        caseId: data.assessment.id,
        expectedInvestigationRevision: data.investigations.revision,
        expectedQuestionnaireRevision: questionnaire.revision,
      );
      reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AppException
              ? error.message
              : 'Current Patient Advice could not be generated.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmHypocalcaemia(
    _RecommendationReviewData data,
    VoidCallback reload,
  ) async {
    if (_hypocalcaemiaDraft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.confirmCaseHypocalcaemia(
        caseId: data.assessment.id,
        value: _hypocalcaemiaDraft!,
        expectedRevision: data.investigations.hypocalcaemiaRevision,
      );
      if (mounted) {
        setState(() => _hypocalcaemiaDraft = null);
        reload();
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(
    _RecommendationReviewData data,
    VoidCallback reload,
  ) async {
    if (_decision == null) {
      setState(() => _error = 'Choose Approve or Withhold.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      setState(
        () => _error = _decision == ClinicalCaseStatus.withheld
            ? 'Enter the reason for withholding this recommendation.'
            : 'Enter the clinician message for the patient.',
      );
      return;
    }
    if (_decision == ClinicalCaseStatus.approved &&
        data.resultsReview == null) {
      setState(
        () => _error =
            'Generate Current Patient Advice before approving this result.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordClinicianDecision(
        assessment: data.assessment,
        decision: _decision!,
        notes: _message.text.trim(),
        resultsReview: data.resultsReview,
      );
      if (mounted) {
        _message.clear();
        _decision = null;
        reload();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Decision saved.')));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AppException
              ? error.message
              : 'Your decision could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(String title, List<Widget> content) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...content,
          ],
        ),
      ),
    ),
  );

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Audit ID: ${trace.pathwayId == null ? "" : "${trace.pathwayId} • "}${trace.ruleId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          if (item.details.isNotEmpty)
            Text(
              item.details.first.startsWith('Rule checked:')
                  ? item.details.first
                  : 'Rule checked: ${item.details.join("; ")}',
            ),
          Text('Result: ${item.result}'),
        ],
      ),
    );
  }

  Widget _whyThisRecommendation(ClinicalCase assessment) {
    final evaluation = assessment.evaluation;
    final explanation = evaluation == null
        ? const <String>[]
        : recommendationExplanation(evaluation);
    return _card('Why this recommendation', [
      if (explanation.isEmpty)
        const Text(
          'A concise explanation is unavailable for this saved assessment. Open the technical trace to review it.',
        ),
      for (final line in explanation)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line)),
      ExpansionTile(
        key: const ValueKey('technical-trace'),
        title: const Text('View technical trace'),
        childrenPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (assessment.clinicianFacts.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Source: Clinician confirmed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final entry in assessment.clinicianFacts.entries)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${const ['knownPoorMedicationAdherence', 'cognitiveImpairment'].contains(entry.key) ? "Historical reference: " : ""}${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                ),
              ),
            const Divider(),
          ],
          if (evaluation != null)
            for (var i = 0; i < evaluation.trace.length; i++)
              _traceTile(assessment, i),
        ],
      ),
    ]);
  }

  Widget _safetyAndDiscussion(ClinicalCase assessment) => Card(
    child: ExpansionTile(
      key: const ValueKey('safety-discussion'),
      title: const Text('Safety and discussion'),
      childrenPadding: const EdgeInsets.all(20),
      children: [
        if (assessment.evaluation?.warnings.isNotEmpty == true)
          for (final warning in assessment.evaluation!.warnings) Text(warning)
        else
          const Text(
            'No treatment-specific safety information was supplied for this assessment.',
          ),
      ],
    ),
  );

  Widget _decisionCard(_RecommendationReviewData data, VoidCallback reload) =>
      _card('Clinician Decision', [
        const Text('Select a decision'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (data.assessment.evaluation?.canApprove == true)
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
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _message,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: _decision == ClinicalCaseStatus.withheld
                ? 'Reason for withholding (clinician review)'
                : 'Clinician message for the patient',
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
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _saving ? null : () => _save(data, reload),
            child: Text(_saving ? 'Saving...' : 'Save decision'),
          ),
        ),
      ]);

  Widget _reviewLayout(List<Widget> sections) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 1000
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        children: [
          for (final section in sections)
            SizedBox(width: width, child: section),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review Result'),
      actions: [GlobalSignOut(repository: widget.repository)],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: AsyncPanel<_RecommendationReviewData>(
            load: _load,
            builder: (data, reload) {
              final assessment = data.assessment;
              final evaluation = assessment.evaluation;
              final adviceIsCurrent =
                  data.resultsReview != null &&
                  data.resultsReview!.adviceContractVersion ==
                      'songyi-advice-20261009' &&
                  data.resultsReview!.hypocalcaemiaRevision ==
                      data.investigations.hypocalcaemiaRevision &&
                  data.resultsReview!.investigationRevision ==
                      data.investigations.revision &&
                  data.resultsReview!.questionnaireRevision ==
                      data.questionnaire?.revision;
              return _reviewLayout([
                _card('Care Recommendation', [
                  if (evaluation == null || !evaluation.canApprove)
                    const Text(
                      'More information is required before the recommendation can be completed.',
                    ),
                  if (evaluation != null && !evaluation.canApprove)
                    for (final key in evaluation.missingInputs)
                      Text(missingRequiredFact(key)),
                  if (evaluation?.canApprove == true)
                    for (final action in evaluation!.actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PathwayActionView(action: action),
                      ),
                ]),
                _whyThisRecommendation(assessment),
                _card('Current Patient Advice', [
                  if (data.investigations.authoritativeHypocalcaemia == null &&
                      assessment.canReview) ...[
                    const Text('Does the patient have hypocalcaemia?'),
                    DropdownButtonFormField<bool>(
                      initialValue: _hypocalcaemiaDraft,
                      decoration: const InputDecoration(
                        hintText: 'Select an answer',
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Yes')),
                        DropdownMenuItem(value: false, child: Text('No')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _hypocalcaemiaDraft = value),
                    ),
                    Text(
                      'Source: Clinician confirmed',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: _saving || _hypocalcaemiaDraft == null
                            ? null
                            : () => _confirmHypocalcaemia(data, reload),
                        child: const Text('Confirm hypocalcaemia status'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (!adviceIsCurrent) ...[
                    const Text(
                      'Current Patient Advice has not been generated for this result.',
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed:
                            _saving ||
                                data
                                        .investigations
                                        .authoritativeHypocalcaemia ==
                                    null ||
                                !assessment.canReview
                            ? null
                            : () => _generateCommonAdvice(data, reload),
                        child: const Text('Generate Current Patient Advice'),
                      ),
                    ),
                  ] else ...[
                    if (data.resultsReview!.calciumAuthorityNeedsConfirmation)
                      const Text(
                        'Calcium advice needs clinical source confirmation. The recorded advice is shown below.',
                      ),
                    for (final advice in currentPatientAdvice(
                      data.resultsReview!,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(advice),
                      ),
                  ],
                ]),
                if (assessment.evaluation?.warnings.isNotEmpty == true)
                  _safetyAndDiscussion(assessment),
                if (assessment.canReview) _decisionCard(data, reload),
                if (assessment.status == ClinicalCaseStatus.approved ||
                    assessment.status == ClinicalCaseStatus.withheld)
                  _card(
                    assessment.status == ClinicalCaseStatus.withheld
                        ? 'Saved withholding decision'
                        : 'Clinician Decision',
                    [
                      const Text('Decision status'),
                      Text(
                        assessment.status == ClinicalCaseStatus.approved
                            ? 'Approved'
                            : 'Withheld',
                      ),
                      if (assessment.decisionNotes?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('Clinician note'),
                        Text(assessment.decisionNotes!),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                        child: const Text('Return to Work Queue'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop(true);
                          } else {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => ClinicianCaseScreen(
                                  caseId: widget.caseId,
                                  repository: widget.repository,
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Back to Patient Overview'),
                      ),
                    ],
                  ),
              ]);
            },
          ),
        ),
      ),
    ),
  );
}

class _RecommendationReviewData {
  const _RecommendationReviewData({
    required this.assessment,
    required this.investigations,
    required this.questionnaire,
    required this.resultsReview,
  });

  final ClinicalCase assessment;
  final CaseInvestigations investigations;
  final QuestionnaireResponse? questionnaire;
  final ClinicalResultsReview? resultsReview;
}
