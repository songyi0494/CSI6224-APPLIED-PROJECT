import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_result_contract.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../utils/clinical_trace_presentation.dart';
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
  final _message = TextEditingController();
  ClinicalCaseStatus? _decision;
  bool _saving = false;
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
              : 'Common Advice could not be generated.',
        );
      }
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
    if (_decision == ClinicalCaseStatus.approved &&
        _message.text.trim().isEmpty) {
      setState(() => _error = 'Enter the clinician message for the patient.');
      return;
    }
    if (_decision == ClinicalCaseStatus.approved &&
        data.resultsReview == null) {
      setState(
        () => _error =
            'Generate current Common Advice before approving this result.',
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
          Text('Result: ${item.result}'),
          if (item.implication != null) Text('Next: ${item.implication}'),
        ],
      ),
    );
  }

  Widget _whyThisResult(ClinicalCase assessment) => Card(
    child: ExpansionTile(
      title: const Text('Why This Result'),
      childrenPadding: const EdgeInsets.all(20),
      children: [
        if (assessment.clinicianFacts.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Clinician-confirmed facts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in assessment.clinicianFacts.entries)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                ),
              ),
            ),
          const Divider(height: 28),
        ],
        if (assessment.evaluation != null)
          for (var i = 0; i < assessment.evaluation!.trace.length; i++)
            _traceTile(assessment, i),
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
          decoration: const InputDecoration(labelText: 'Clinician message'),
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review Result')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: AsyncPanel<_RecommendationReviewData>(
            load: _load,
            builder: (data, reload) {
              final assessment = data.assessment;
              final evaluation = assessment.evaluation;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card('Care Recommendation', [
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
                  _whyThisResult(assessment),
                  const SizedBox(height: 16),
                  _card('Common Advice', [
                    if (data.resultsReview == null) ...[
                      const Text(
                        'Current Common Advice has not been generated for this result.',
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _generateCommonAdvice(data, reload),
                          child: const Text('Generate Common Advice'),
                        ),
                      ),
                    ] else
                      for (final advice in data.resultsReview!.commonAdvice)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(advice),
                        ),
                  ]),
                  if (assessment.canReview) _decisionCard(data, reload),
                ],
              );
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
