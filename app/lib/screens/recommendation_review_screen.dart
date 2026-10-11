import '../widgets/pathway_action_view.dart';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';
import '../models/clinical_case.dart';
import '../models/clinical_result_contract.dart';
import '../models/questionnaire.dart';
import '../utils/clinical_labels.dart';
import '../utils/clinical_trace_presentation.dart';
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

class _RecommendationReviewScreenState extends State<RecommendationReviewScreen> {
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
    if (_message.text.trim().isEmpty) {
      setState(() => _error = _decision == ClinicalCaseStatus.withheld
          ? 'Enter the reason for withholding this recommendation.'
          : 'Enter the clinician message for the patient.');
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

  // Display-only mapping: the backend remains responsible for evaluating rules.
  static const _traceFactKeys = <String, List<String>>{
    'PATHWAY1:RENAL_DYSFUNCTION': ['eGFR'],
    'PATHWAY1:ON_OSTEOPOROSIS_TREATMENT': ['osteoporosisTreatmentStatus'],
    'PATHWAY1:RESIDENTIAL_OR_FRAILTY': [
      'liveInResidentialCare', 'clinicalFrailtyScore', 'lifeExpectancy',
    ],
    'PATHWAY1:ADHERENCE_CONCERN': [
      'knownPoorMedicationAdherence', 'cognitiveImpairment',
    ],
    'PATHWAY1:DXA_SCAN_AVAILABILITY': ['testAvailability'],
    'PATHWAY1:T_SCORE_CHECK': [
      'femoralNeckTscore', 'hipTscore', 'lumbarSpineTscore',
    ],
    'PATHWAY1:RECENT_MAJOR_FRACTURES': [
      'hipVertebralOrMultipleFracturesInLast24M',
    ],
    'PATHWAY2:ON_ANTIRESORPTIVE_TREATMENT': ['antiresorptiveTreatmentStatus'],
    'PATHWAY2:ANTIRESORPTIVE_TREATMENT_DURATION': ['antiresorptiveTreatmentDuration'],
    'PATHWAY2:TREATMENT_ADHERENCE': ['adheredToTheTreatment'],
    'PATHWAY2:SYMPTOMATIC_FRACTURE': ['symptomaticFractureInLast12M'],
    'PATHWAY2:MULTIPLE_FRACTURES': ['multipleFractures'],
    'PATHWAY2:CHECK_BMD': ['lowBMD'],
    'PATHWAY2:MI_OR_STROKE_HISTORY': ['priorMIorStroke'],
    'PATHWAY2:SEQUENCING_WITH_HISTORY': ['sequencingFromDenosumab'],
    'PATHWAY2:SEQUENCING_NO_HISTORY': ['sequencingFromDenosumab'],
    'PATHWAY1:HIGH_RISK_CHECK': [
      'femoralNeckTscore', 'hipTscore', 'lumbarSpineTscore',
      'recentFractureWithin2Y', 'historyOf2orMoreFractures',
      'clinicalRiskFactors', 'FRAX10YmajorOsteoporoticFractureRiskPercent',
      'FRAX10YmajorHipFractureRiskPercent',
    ],
  };

  Widget _traceTile(ClinicalCase assessment, int index, int displayNumber) {
    final trace = assessment.evaluation!.trace[index];
    final item = clinicalTracePresentation(
      trace,
      clinicianInput: assessment.clinicianInput,
    );
    final factKeys = _traceFactKeys['${trace.pathwayId}:${trace.ruleId}'];
    // Do not substitute unrelated facts for a missing value.
    final facts = <MapEntry<String, Object?>>[
      if (factKeys != null)
        for (final key in factKeys)
          if (assessment.clinicianFacts.containsKey(key))
            MapEntry(key, assessment.clinicianFacts[key]),
      if (factKeys == null)
        for (final entry in trace.input.entries) entry,
    ];
    final isLeaf = trace.nodeType == 'leaf';
    final ruleLines = item.details.where(
      (detail) => detail.startsWith('Rule checked:'),
    );
    final otherLines = item.details.where(
      (detail) => !detail.startsWith('Rule checked:'),
    );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$displayNumber. ${trace.pathwayId ?? "Pathway"}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(item.title, style: theme.textTheme.titleMedium),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final fact in facts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${clinicalLabel(fact.key)}:',
                            style: theme.textTheme.bodyMedium),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            factText(fact.value),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (ruleLines.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rule checked', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      for (final line in ruleLines)
                        Text(line.substring('Rule checked:'.length).trim()),
                    ],
                  ),
                ),
              ],
              // Legacy trace entries may contain useful non-rule details.
              for (final line in otherLines)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(line),
                ),
              if (isLeaf) ...[
                const SizedBox(height: 8),
                Text(item.result, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }

  // Hide only redirect entries from the presentation, not final treatment leaves.
  bool _isRedirectTrace(int index, ClinicalCase assessment) {
    final trace = assessment.evaluation!.trace[index];
    return trace.nodeType == 'leaf' &&
        (trace.ruleId.startsWith('LEAF_REDIRECT_PATHWAY') ||
            trace.actionsTriggered.any(
              (action) => action.type == 'pathwayRedirect',
            ));
  }

  Widget _whyThisResult(ClinicalCase assessment) {
    final visibleIndexes = <int>[
      if (assessment.evaluation != null)
        for (var i = 0; i < assessment.evaluation!.trace.length; i++)
          if (!_isRedirectTrace(i, assessment)) i,
    ];
    return Card(
      child: ExpansionTile(
        title: const Text('Why This Result'),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < visibleIndexes.length; i++)
            _traceTile(assessment, visibleIndexes[i], i + 1),
        ],
      ),
    );
  }

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
                          child: PathwayActionView(action: action),
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
