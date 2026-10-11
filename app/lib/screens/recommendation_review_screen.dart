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
    padding: const EdgeInsets.only(bottom: 12),
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

  String _pathwayName(ClinicalCase assessment) {
    final pathway = assessment.evaluation?.pathway;
    if (pathway == 'PATHWAY1') return 'Pathway 1';
    if (pathway == 'PATHWAY2') return 'Pathway 2';
    if (assessment.pathway == ClinicalPathway.pathway1) return 'Pathway 1';
    if (assessment.pathway == ClinicalPathway.pathway2) return 'Pathway 2';
    return 'Not recorded';
  }

  String _resultSummary(ClinicalCase assessment) {
    if (assessment.status == ClinicalCaseStatus.approved) {
      return 'The clinician approved this result.';
    }
    if (assessment.status == ClinicalCaseStatus.withheld) {
      return 'The clinician withheld this result.';
    }
    final evaluation = assessment.evaluation;
    if (evaluation == null) {
      return 'No evaluated care result is available.';
    }
    if (evaluation.missingInputs.isNotEmpty) {
      return 'More information is required. Review the missing inputs below.';
    }
    if (evaluation.warnings.isNotEmpty) {
      return 'Review the warnings before you record a decision.';
    }
    if (evaluation.canApprove) {
      return 'Review the proposed care actions. Then record your decision.';
    }
    return 'This result is not ready for approval. Review the details.';
  }

  Widget _status(ClinicalCaseStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final approved = status == ClinicalCaseStatus.approved;
    final withheld = status == ClinicalCaseStatus.withheld;
    final label = approved
        ? 'Approved'
        : withheld
        ? 'Withheld'
        : status.label;
    return Semantics(
      label: 'Saved case status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: withheld ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              approved
                  ? Icons.check_circle_outline
                  : withheld
                  ? Icons.block_outlined
                  : Icons.info_outline,
              size: 18,
              color: withheld
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: withheld
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clinicalSummary(_RecommendationReviewData data) {
    final assessment = data.assessment;
    final evaluation = assessment.evaluation;
    final answers = data.questionnaire?.answers;
    final reportedFracture = answers?['minimalTraumaFracture'];
    final adultFracture = answers?['adultFractureHistory'];
    final currentTreatment =
        assessment.clinicianFacts['osteoporosisTreatmentStatus'];
    final kidneyFunction = assessment.clinicianFacts['eGFR'];
    final recentMajorFracture =
        assessment.clinicianFacts['hipVertebralOrMultipleFracturesInLast24M'];
    final veryHighRisk = assessment.clinicianFacts['highRisk'];
    return _card('Clinical Summary', [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            assessment.patientName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Clinical pathway: ${_pathwayName(assessment)}'),
          if (assessment.status != ClinicalCaseStatus.approved &&
              assessment.status != ClinicalCaseStatus.withheld)
            _status(assessment.status),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 24,
        runSpacing: 4,
        children: [
          if (reportedFracture != null)
            Text(
              'Minimal-trauma fracture (patient report): ${factText(reportedFracture)}',
            ),
          if (adultFracture != null)
            Text(
              'Adult fracture history (patient report): ${factText(adultFracture)}',
            ),
          if (currentTreatment != null)
            Text(
              '${clinicalLabel('osteoporosisTreatmentStatus')} (clinician fact): ${factText(currentTreatment)}',
            ),
          if (kidneyFunction is bool)
            Text('eGFR (recorded clinician value): ${factText(kidneyFunction)}')
          else if (kidneyFunction is num)
            Text('eGFR (clinician): $kidneyFunction mL/min'),
          if (recentMajorFracture != null)
            Text(
              '${clinicalLabel('hipVertebralOrMultipleFracturesInLast24M')} (clinician fact): ${factText(recentMajorFracture)}',
            ),
          if (veryHighRisk != null)
            Text(
              'Very high fracture risk (clinician fact): ${factText(veryHighRisk)}',
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (assessment.status != ClinicalCaseStatus.approved &&
          assessment.status != ClinicalCaseStatus.withheld)
        Text(_resultSummary(assessment)),
      if (evaluation != null && evaluation.missingInputs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Missing information',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final field in evaluation.missingInputs)
          Text('• ${clinicalLabel(field)}'),
      ],
      if (evaluation != null && evaluation.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text('Warnings', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        for (final warning in evaluation.warnings) Text('• $warning'),
      ],
      if (data.resultsReview == null) ...[
        const SizedBox(height: 4),
        const Text(
          'Common Advice: Not generated. Generate it before approval.',
        ),
      ],
    ]);
  }

  // Display-only mapping: the backend remains responsible for evaluating rules.
  static const _traceFactKeys = <String, List<String>>{
    'PATHWAY1:RENAL_DYSFUNCTION': ['eGFR'],
    'PATHWAY1:ON_OSTEOPOROSIS_TREATMENT': ['osteoporosisTreatmentStatus'],
    'PATHWAY1:RESIDENTIAL_OR_FRAILTY': [
      'liveInResidentialCare',
      'clinicalFrailtyScore',
      'lifeExpectancy',
    ],
    'PATHWAY1:ADHERENCE_CONCERN': [
      'knownPoorMedicationAdherence',
      'cognitiveImpairment',
    ],
    'PATHWAY1:DXA_SCAN_AVAILABILITY': ['testAvailability'],
    'PATHWAY1:T_SCORE_CHECK': [
      'femoralNeckTscore',
      'hipTscore',
      'lumbarSpineTscore',
    ],
    'PATHWAY1:RECENT_MAJOR_FRACTURES': [
      'hipVertebralOrMultipleFracturesInLast24M',
    ],
    'PATHWAY2:ON_ANTIRESORPTIVE_TREATMENT': ['antiresorptiveTreatmentStatus'],
    'PATHWAY2:ANTIRESORPTIVE_TREATMENT_DURATION': [
      'antiresorptiveTreatmentDuration',
    ],
    'PATHWAY2:TREATMENT_ADHERENCE': ['adheredToTheTreatment'],
    'PATHWAY2:SYMPTOMATIC_FRACTURE': ['symptomaticFractureInLast12M'],
    'PATHWAY2:MULTIPLE_FRACTURES': ['multipleFractures'],
    'PATHWAY2:CHECK_BMD': ['lowBMD'],
    'PATHWAY2:MI_OR_STROKE_HISTORY': ['priorMIorStroke'],
    'PATHWAY2:SEQUENCING_WITH_HISTORY': ['sequencingFromDenosumab'],
    'PATHWAY2:SEQUENCING_NO_HISTORY': ['sequencingFromDenosumab'],
    'PATHWAY1:HIGH_RISK_CHECK': [
      'femoralNeckTscore',
      'hipTscore',
      'lumbarSpineTscore',
      'recentFractureWithin2Y',
      'historyOf2orMoreFractures',
      'clinicalRiskFactors',
      'FRAX10YmajorOsteoporoticFractureRiskPercent',
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
        for (final entry in trace.input.entries)
          if (clinicalLabel(entry.key) != entry.key || entry.key == 'eGFR')
            entry,
    ];
    final isLeaf = trace.nodeType == 'leaf';
    final ruleLines = item.details
        .where((detail) => detail.startsWith('Rule checked:'))
        .map(
          (line) => line
              .replaceAll('eGFR >= 30', 'eGFR >= 30 mL/min')
              .replaceAll(
                'FRAX 10-year major osteoporotic fracture risk >= 30',
                'FRAX 10-year major osteoporotic fracture risk >= 30%',
              )
              .replaceAll(
                'FRAX 10-year hip fracture risk >= 4.5',
                'FRAX 10-year hip fracture risk >= 4.5%',
              ),
        );
    final otherLines = item.details.where(
      (detail) => !detail.startsWith('Rule checked:'),
    );
    final pathway = trace.pathwayId == 'PATHWAY1'
        ? 'Pathway 1'
        : trace.pathwayId == 'PATHWAY2'
        ? 'Pathway 2'
        : 'Pathway';
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('trace-step-$index'),
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
                  '$displayNumber. $pathway',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title == trace.ruleId
                      ? (isLeaf
                            ? 'Recorded care outcome'
                            : 'Clinical rule check')
                      : item.title,
                  style: theme.textTheme.titleMedium,
                ),
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
                          Text(
                            '${clinicalLabel(fact.key)}:',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _clinicalFactValue(fact.key, fact.value),
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
                        Text(
                          'Rule checked',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        for (final line in ruleLines)
                          Text(line.substring('Rule checked:'.length).trim()),
                      ],
                    ),
                  ),
                ],
                // Legacy trace entries may contain useful non-rule details.
                for (final line in otherLines.where(
                  (line) => !trace.input.keys.any(
                    (key) =>
                        clinicalLabel(key) == key &&
                        key != 'eGFR' &&
                        line.startsWith('$key:'),
                  ),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(line),
                  ),
                const SizedBox(height: 8),
                Text(
                  isLeaf ? 'Terminal outcome recorded.' : item.result,
                  style: theme.textTheme.bodyMedium,
                ),
                for (final action in trace.actionsTriggered)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PathwayActionView(
                      action: action,
                      compactMedications: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _clinicalFactValue(String key, Object? value) {
    if (value is num && key == 'eGFR') return '$value mL/min';
    if (value is num && key.startsWith('FRAX') && key.endsWith('Percent')) {
      return '$value%';
    }
    if (key == 'sex') return sexAtBirthText(value?.toString());
    if (key == 'tScoreSite') return factText(value).replaceAll('_', ' ');
    return factText(value);
  }

  Widget _whyThisResult(ClinicalCase assessment) {
    final evaluation = assessment.evaluation;
    return Card(
      child: ExpansionTile(
        key: const ValueKey('decision-trace'),
        title: const Text('Decision trace'),
        subtitle: const Text(
          'Open the clinician facts and recorded rule checks.',
        ),
        childrenPadding: const EdgeInsets.all(16),
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
              if (clinicalLabel(entry.key) != entry.key || entry.key == 'eGFR')
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${clinicalLabel(entry.key)}: ${_clinicalFactValue(entry.key, entry.value)}',
                    ),
                  ),
                ),
            const Divider(height: 28),
          ],
          if (evaluation == null || evaluation.trace.isEmpty)
            const Text('No decision trace is available for this result.'),
          if (evaluation != null)
            for (var i = 0; i < evaluation.trace.length; i++)
              _traceTile(assessment, i, i + 1),
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

  Widget _careRecommendation(ClinicalCase assessment) {
    final evaluation = assessment.evaluation;
    return _card('Care Recommendation', [
      if (evaluation == null || evaluation.actions.isEmpty)
        const Text('No recommendation is available for approval.'),
      if (evaluation != null)
        for (final action in evaluation.actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PathwayActionView(action: action, compactMedications: true),
          ),
    ]);
  }

  Widget _commonAdvice(
    _RecommendationReviewData data,
    VoidCallback reload,
  ) => _card('Common Advice', [
    if (data.resultsReview == null) ...[
      const Text(
        'Current Common Advice has not been generated for this result.',
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: _saving ? null : () => _generateCommonAdvice(data, reload),
          child: const Text('Generate Common Advice'),
        ),
      ),
    ] else
      for (final advice in data.resultsReview!.commonAdvice)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(advice)),
  ]);

  Widget _savedDecision(ClinicalCase assessment) => _card(
    assessment.status == ClinicalCaseStatus.withheld
        ? 'Saved withholding decision'
        : 'Clinician Decision',
    [
      const Text('Decision status'),
      const SizedBox(height: 4),
      Align(
        key: const ValueKey('saved-decision-status'),
        alignment: Alignment.centerLeft,
        child: _status(assessment.status),
      ),
      if (assessment.decisionNotes?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        Text('Clinician note', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        SelectableText(
          assessment.decisionNotes!,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    ],
  );

  Widget _navigation() => LayoutBuilder(
    builder: (_, constraints) {
      final buttons = <Widget>[
        FilledButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('Return to Work Queue'),
        ),
        const SizedBox(width: 12, height: 8),
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
      ];
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: constraints.maxWidth >= 1000
            ? Row(children: buttons)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review Result'),
      actions: [GlobalSignOut(repository: widget.repository)],
    ),
    body: DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            key: const ValueKey('review-content'),
            constraints: const BoxConstraints(maxWidth: 1280),
            child: AsyncPanel<_RecommendationReviewData>(
              load: _load,
              builder: (data, reload) {
                final assessment = data.assessment;
                final finalDecision =
                    assessment.status == ClinicalCaseStatus.approved ||
                    assessment.status == ClinicalCaseStatus.withheld;
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _commonAdvice(data, reload),
                    if (assessment.canReview) _decisionCard(data, reload),
                    if (finalDecision) _savedDecision(assessment),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _clinicalSummary(data),
                    LayoutBuilder(
                      builder: (_, constraints) => constraints.maxWidth >= 1000
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 65,
                                  child: _careRecommendation(assessment),
                                ),
                                const SizedBox(width: 16),
                                Expanded(flex: 35, child: right),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _careRecommendation(assessment),
                                right,
                              ],
                            ),
                    ),
                    _whyThisResult(assessment),
                    if (finalDecision) _navigation(),
                  ],
                );
              },
            ),
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
