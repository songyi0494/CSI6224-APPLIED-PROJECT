import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../models/live_pathway.dart';

class PathwayQuestionScreen extends StatefulWidget {
  const PathwayQuestionScreen({
    required this.caseId,
    required this.repository,
    super.key,
  });
  final String caseId;
  final AppRepository repository;

  @override
  State<PathwayQuestionScreen> createState() => _PathwayQuestionScreenState();
}

class _PathwayQuestionScreenState extends State<PathwayQuestionScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, Object?> _draft = {};
  final Map<String, TextEditingController> _controllers = {};
  ClinicalCase? _case;
  PathwayQuestionStep? _step;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _case = await widget.repository.fetchClinicalCase(widget.caseId);
      final result = await widget.repository.evaluatePathway(
        caseId: widget.caseId,
      );
      if (!mounted) return;
      if (result is CompletedPathwayEvaluation) {
        Navigator.pop(context, true);
      } else if (result is PathwayQuestionStep) {
        _setStep(result);
      } else {
        _error = (result as PathwayRuntimeError).message;
      }
    } on AppException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'The pathway could not be loaded. Reload the case and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStep(PathwayQuestionStep step) {
    _step = step;
    _draft.clear();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    final stored = _case?.clinicianFacts ?? const <String, Object?>{};
    for (final key in step.requiredFacts) {
      final definition = pathwayFactRegistry[key];
      if (definition == null)
        throw AppException('The pathway requested unsupported field "$key".');
      _draft[key] = stored[key];
      if (definition.kind == PathwayFactKind.number) {
        _controllers[key] = TextEditingController(
          text: stored[key]?.toString() ?? '',
        );
      }
    }
  }

  Object? _valueFor(String key) {
    final definition = pathwayFactRegistry[key]!;
    if (definition.kind == PathwayFactKind.boolean) return _draft[key];
    final raw = _controllers[key]!.text.trim();
    if (raw.isEmpty) return null;
    return definition.wholeNumber ? int.tryParse(raw) : double.tryParse(raw);
  }

  Future<void> _next() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final values = <String, Object>{};
    for (final key in _step!.requiredFacts) {
      final value = _valueFor(key);
      if (value == null) return;
      values[key] = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stored = _case?.clinicianFacts ?? const <String, Object?>{};
      for (final entry in values.entries) {
        if (stored[entry.key] != entry.value) {
          await widget.repository.savePathwayAnswer(
            caseId: widget.caseId,
            fieldKey: entry.key,
            value: entry.value,
          );
        }
      }
      _case = await widget.repository.fetchClinicalCase(widget.caseId);
      final result = await widget.repository.evaluatePathway(
        caseId: widget.caseId,
      );
      if (!mounted) return;
      if (result is CompletedPathwayEvaluation) {
        Navigator.pop(context, true);
      } else if (result is PathwayQuestionStep) {
        setState(() => _setStep(result));
      } else {
        setState(() => _error = (result as PathwayRuntimeError).message);
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Set<String> get _activeFactKeys {
    final keys = <String>{...?_step?.requiredFacts};
    for (final entry in _step?.trace ?? const <LivePathwayTraceEntry>[]) {
      keys.addAll(_nodeFacts[entry.nodeId] ?? const []);
    }
    return keys;
  }

  Future<void> _editPrevious(String key) async {
    final definition = pathwayFactRegistry[key]!;
    final current = _case!.clinicianFacts[key];
    Object? value = current;
    final controller = TextEditingController(text: current?.toString() ?? '');
    final changed = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${definition.label}'),
          content: definition.kind == PathwayFactKind.boolean
              ? DropdownButtonFormField<bool>(
                  initialValue: value as bool?,
                  decoration: const InputDecoration(
                    labelText: 'Clinician-confirmed value',
                  ),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Yes')),
                    DropdownMenuItem(value: false, child: Text('No')),
                  ],
                  onChanged: (next) => setDialogState(() => value = next),
                )
              : TextField(
                  controller: controller,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !definition.wholeNumber,
                    signed: definition.allowNegative,
                  ),
                  decoration: InputDecoration(
                    labelText: definition.label,
                    suffixText: definition.unit,
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (definition.kind == PathwayFactKind.number) {
                  value = definition.wholeNumber
                      ? int.tryParse(controller.text.trim())
                      : double.tryParse(controller.text.trim());
                }
                if (value != null) Navigator.pop(dialogContext, value);
              },
              child: const Text('Save & re-evaluate'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (changed == null || changed == current || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.savePathwayAnswer(
        caseId: widget.caseId,
        fieldKey: key,
        value: changed,
      );
      await _load();
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _control(String key) {
    final definition = pathwayFactRegistry[key]!;
    if (definition.kind == PathwayFactKind.boolean) {
      return DropdownButtonFormField<bool>(
        key: ValueKey('$key-${_draft[key]}'),
        initialValue: _draft[key] as bool?,
        decoration: InputDecoration(labelText: definition.label),
        items: const [
          DropdownMenuItem(value: true, child: Text('Yes')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() => _draft[key] = value),
        validator: (value) =>
            value == null ? 'Clinician confirmation is required' : null,
      );
    }
    return TextFormField(
      key: ValueKey(key),
      controller: _controllers[key],
      enabled: !_busy,
      keyboardType: TextInputType.numberWithOptions(
        decimal: !definition.wholeNumber,
        signed: definition.allowNegative,
      ),
      decoration: InputDecoration(
        labelText: definition.label,
        suffixText: definition.unit,
      ),
      validator: (raw) {
        final text = raw?.trim() ?? '';
        if (text.isEmpty) return 'Clinician confirmation is required';
        final number = num.tryParse(text);
        if (number == null || !number.isFinite) return 'Enter a valid number';
        if (definition.wholeNumber && int.tryParse(text) == null)
          return 'Enter a whole number';
        if (!definition.allowNegative && number < 0)
          return 'Enter zero or a positive number';
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final previous = step == null || _case == null
        ? const <String>[]
        : _activeFactKeys
              .where(
                (key) =>
                    !step.requiredFacts.contains(key) &&
                    _case!.clinicianFacts.containsKey(key),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Clinical pathway')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy && step == null) const LinearProgressIndicator(),
              if (step != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            step.question,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Confirm every required fact below. Patient-reported information is not automatically treated as clinician-confirmed.',
                          ),
                          const SizedBox(height: 20),
                          for (final key in step.requiredFacts) ...[
                            _control(key),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (previous.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      title: const Text('Previous answers'),
                      subtitle: const Text(
                        'Editable only while this case is in progress',
                      ),
                      children: [
                        for (final key in previous)
                          ListTile(
                            title: Text(pathwayFactRegistry[key]!.label),
                            subtitle: Text(
                              _case!.clinicianFacts[key].toString(),
                            ),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _editPrevious(key),
                              child: const Text('Edit'),
                            ),
                          ),
                      ],
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Exit pathway'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _busy ? null : _next,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(_busy ? 'Evaluating…' : 'Next'),
                    ),
                  ],
                ),
              ],
              if (_error != null && step == null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _nodeFacts = <String, List<String>>{
    'RENAL_DYSFUNCTION': ['eGFR'],
    'ON_OSTEOPOROSIS_TREATMENT': ['osteoporosisTreatmentStatus'],
    'RESIDENTIAL_OR_FRAILTY': [
      'liveInResidentialCare',
      'clinicalFrailtyScore',
      'lifeExpectancy',
    ],
    'ADHERENCE_CONCERN': [
      'knownPoorMedicationAdherence',
      'cognitiveImpairment',
    ],
    'DXA_SCAN_AVAILABILITY': ['testAvailability'],
    'T_SCORE_CHECK': ['femoralNeckTscore', 'hipTscore', 'lumbarSpineTscore'],
    'RECENT_MAJOR_FRACTURES': ['hipVertebralOrMultipleFracturesInLast24M'],
    'HIGH_RISK_CHECK': [
      'femoralNeckTscore',
      'hipTscore',
      'lumbarSpineTscore',
      'recentFractureWithin2Y',
      'historyOf2orMoreFractures',
      'clinicalRiskFactors',
      'FRAX10YmajorOsteoporoticFractureRiskPercent',
      'FRAX10YmajorHipFractureRiskPercent',
    ],
    'ON_ANTIRESORPTIVE_TREATMENT': ['antiresorptiveTreatmentStatus'],
    'ANTIRESORPTIVE_DURATION': ['antiresorptiveTreatmentDuration'],
    'TREATMENT_ADHERENCE': ['adheredToTheTreatment'],
    'SYMPTOMATIC_FRACTURE': ['symptomaticFractureInLast12M'],
    'MULTIPLE_FRACTURES': ['multipleFractures'],
    'LOW_BMD': ['lowBMD'],
    'PRIOR_MI_OR_STROKE': ['priorMIorStroke'],
    'SEQUENCING_FROM_DENOSUMAB': ['sequencingFromDenosumab'],
  };
}
