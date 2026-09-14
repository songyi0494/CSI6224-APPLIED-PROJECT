import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../models/pathway1_clinician_input.dart';
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
  final _notes = TextEditingController();
  final _clinicianForm = GlobalKey<FormState>();
  final Map<String, TextEditingController> _clinicalNumbers = {
    'eGFR': TextEditingController(),
    'clinicalFrailtyScore': TextEditingController(),
    'lifeExpectancy': TextEditingController(),
    'tScoreValue': TextEditingController(),
    'yearsSinceMenopause': TextEditingController(),
  };
  final Map<String, Object?> _clinicalAnswers = {};
  ClinicalCaseStatus? _decision;
  bool _saving = false;
  String? _error;
  String? _clinicalInputKey;
  @override
  void dispose() {
    _notes.dispose();
    for (final controller in _clinicalNumbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _ensureClinicalInputLoaded(ClinicalCase assessment) {
    final key =
        '${assessment.id}:${assessment.revision}:${assessment.updatedAt.toIso8601String()}';
    if (_clinicalInputKey == key) return;
    _clinicalInputKey = key;
    final input = assessment.clinicianInput ?? const Pathway1ClinicianInput();
    _clinicalNumbers['eGFR']!.text = input.egfr?.toString() ?? '';
    _clinicalNumbers['clinicalFrailtyScore']!.text =
        input.clinicalFrailtyScore?.toString() ?? '';
    _clinicalNumbers['lifeExpectancy']!.text =
        input.lifeExpectancy?.toString() ?? '';
    _clinicalNumbers['tScoreValue']!.text = input.tScoreValue?.toString() ?? '';
    _clinicalNumbers['yearsSinceMenopause']!.text =
        input.yearsSinceMenopause?.toString() ?? '';
    _clinicalAnswers
      ..clear()
      ..addAll({
        'knownPoorMedicationAdherence': input.knownPoorMedicationAdherence,
        'cognitiveImpairment': input.cognitiveImpairment,
        'dxaDoneWithinPrevious2Years': input.dxaDoneWithinPrevious2Years,
        'dxaImpractical': input.dxaImpractical,
        'tScoreSite': input.tScoreSite,
        'hipVertebralOrMultipleFracturesInLast24M':
            input.hipVertebralOrMultipleFracturesInLast24M,
        'clinicianConfirmedVeryHighRisk': input.clinicianConfirmedVeryHighRisk,
        'robustWoman': input.robustWoman,
      });
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

  Future<void> _completeClinicalInput(
    ClinicalCase assessment,
    VoidCallback reload,
  ) async {
    if (!_clinicianForm.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.completePathway1ClinicianInput(
        assessment: assessment,
        input: _clinicianInputFromForm(),
      );
      if (mounted) {
        reload();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Clinical input saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'Clinical input could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Pathway1ClinicianInput _clinicianInputFromForm() => Pathway1ClinicianInput(
    egfr: _doubleValue('eGFR'),
    clinicalFrailtyScore: _intValue('clinicalFrailtyScore'),
    lifeExpectancy: _doubleValue('lifeExpectancy'),
    knownPoorMedicationAdherence:
        _clinicalAnswers['knownPoorMedicationAdherence'] as bool?,
    cognitiveImpairment: _clinicalAnswers['cognitiveImpairment'] as bool?,
    dxaDoneWithinPrevious2Years:
        _clinicalAnswers['dxaDoneWithinPrevious2Years'] as bool?,
    dxaImpractical: _clinicalAnswers['dxaImpractical'] as bool?,
    tScoreValue: _doubleValue('tScoreValue'),
    tScoreSite: _clinicalAnswers['tScoreSite'] as String?,
    hipVertebralOrMultipleFracturesInLast24M:
        _clinicalAnswers['hipVertebralOrMultipleFracturesInLast24M'] as bool?,
    clinicianConfirmedVeryHighRisk:
        _clinicalAnswers['clinicianConfirmedVeryHighRisk'] as bool?,
    yearsSinceMenopause: _doubleValue('yearsSinceMenopause'),
    robustWoman: _clinicalAnswers['robustWoman'] as bool?,
  );

  double? _doubleValue(String key) {
    final raw = _clinicalNumbers[key]!.text.trim();
    return raw.isEmpty ? null : double.parse(raw);
  }

  int? _intValue(String key) {
    final raw = _clinicalNumbers[key]!.text.trim();
    return raw.isEmpty ? null : int.parse(raw);
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

  Widget _number(String key, {bool signed = false, bool whole = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _clinicalNumbers[key],
          decoration: InputDecoration(
            labelText: clinicalLabel(key),
            hintText: 'Leave blank if not confirmed',
          ),
          keyboardType: TextInputType.numberWithOptions(
            decimal: !whole,
            signed: signed,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final number = double.tryParse(value);
            if (number == null || !number.isFinite) {
              return 'Enter a valid number';
            }
            if (whole && int.tryParse(value) == null) {
              return 'Enter a whole number';
            }
            if (!signed && number < 0) return 'Enter zero or a positive number';
            return null;
          },
        ),
      );

  Widget _boolean(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: _clinicalAnswers[key] == null
          ? 'unknown'
          : _clinicalAnswers[key] == true
          ? 'yes'
          : 'no',
      decoration: InputDecoration(labelText: clinicalLabel(key)),
      isExpanded: true,
      items: const [
        DropdownMenuItem(
          value: 'unknown',
          child: Text('Not yet assessed / unknown'),
        ),
        DropdownMenuItem(value: 'yes', child: Text('Yes')),
        DropdownMenuItem(value: 'no', child: Text('No')),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(
              () => _clinicalAnswers[key] = value == 'yes'
                  ? true
                  : value == 'no'
                  ? false
                  : null,
            ),
    ),
  );

  Widget _tScoreSite() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: _clinicalAnswers['tScoreSite'] as String?,
      decoration: InputDecoration(labelText: clinicalLabel('tScoreSite')),
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'femoral_neck', child: Text('Femoral neck')),
        DropdownMenuItem(value: 'hip', child: Text('Hip')),
        DropdownMenuItem(value: 'lumbar_spine', child: Text('Lumbar spine')),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() => _clinicalAnswers['tScoreSite'] = value),
    ),
  );

  Widget _clinicalInputCard(ClinicalCase assessment, VoidCallback reload) {
    final missing = assessment.evaluation?.missingInputs ?? const <String>[];
    return _card('Clinician clinical input', [
      const Text(
        'Enter clinical-record facts before running the Pathway 1 evaluator.',
      ),
      const SizedBox(height: 12),
      Form(
        key: _clinicianForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _number('eGFR'),
            _number('clinicalFrailtyScore', whole: true),
            _number('lifeExpectancy'),
            _boolean('knownPoorMedicationAdherence'),
            _boolean('cognitiveImpairment'),
            _boolean('dxaImpractical'),
            _boolean('dxaDoneWithinPrevious2Years'),
            _number('tScoreValue', signed: true),
            _tScoreSite(),
            _boolean('hipVertebralOrMultipleFracturesInLast24M'),
            _number('yearsSinceMenopause'),
            if (missing.contains('isRobustWoman')) _boolean('robustWoman'),
            if (missing.contains('highRisk'))
              _boolean('clinicianConfirmedVeryHighRisk'),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: _saving
                ? null
                : () => _completeClinicalInput(assessment, reload),
            child: Text(_saving ? 'Saving...' : 'Run Pathway 1 evaluation'),
          ),
          OutlinedButton(
            onPressed: _saving ? null : reload,
            child: const Text('Reload assessment'),
          ),
        ],
      ),
    ]);
  }

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
              _ensureClinicalInputLoaded(a);
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
                  if (a.clinicianInput != null)
                    _card('Clinician-entered facts', [
                      for (final entry in a.clinicianInput!.toJson().entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${clinicalLabel(entry.key)}: ${factText(entry.value)}',
                          ),
                        ),
                    ]),
                  if (a.needsClinicianInput) _clinicalInputCard(a, reload),
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
                      for (var i = 0; i < evaluation.trace.length; i++)
                        _traceTile(a, i),
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
