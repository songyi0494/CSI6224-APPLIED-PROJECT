import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/clinical_case.dart';
import '../models/pathway_evaluation.dart';

class PathwayFormScreen extends StatefulWidget {
  const PathwayFormScreen({
    required this.repository,
    required this.onEvaluationReady,
    this.existingCaseId,
    super.key,
  });

  final AppRepository repository;
  final String? existingCaseId;
  final void Function(ClinicalCase clinicalCase, PathwayEvaluation evaluation)
      onEvaluationReady;

  @override
  State<PathwayFormScreen> createState() => _PathwayFormScreenState();
}

class _PathwayFormScreenState extends State<PathwayFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _patientNameController = TextEditingController(text: 'Avery Martin');
  final _ageController = TextEditingController(text: '74');
  final _egfrController = TextEditingController(text: '54');
  final _frailtyController = TextEditingController(text: '4');
  final _lifeExpectancyController = TextEditingController(text: '10');
  final _tScoreController = TextEditingController(text: '-2.7');

  ClinicalPathway _pathway = ClinicalPathway.pathway1;
  String _sex = 'female';
  String _fractureSite = 'hip';
  bool _postmenopausal = true;
  bool _minimalTraumaFracture = true;
  bool _onOsteoporosisTreatment = false;
  bool _residentialCare = false;
  bool _poorAdherence = false;
  bool _cognitiveImpairment = false;
  bool _dxaAvailable = true;
  bool _dxaWithinTwoYears = true;
  bool _majorRecentFracture = true;
  bool _highRisk = true;
  bool _loading = false;

  @override
  void dispose() {
    _patientNameController.dispose();
    _ageController.dispose();
    _egfrController.dispose();
    _frailtyController.dispose();
    _lifeExpectancyController.dispose();
    _tScoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pathway clinical input')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient and pathway',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _patientNameController,
                      decoration: const InputDecoration(
                        labelText: 'Patient name',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ClinicalPathway>(
                      segments: const [
                        ButtonSegment(
                          value: ClinicalPathway.pathway1,
                          label: Text('Pathway 1'),
                        ),
                        ButtonSegment(
                          value: ClinicalPathway.pathway2,
                          label: Text('Pathway 2'),
                        ),
                      ],
                      selected: {_pathway},
                      onSelectionChanged: (value) => setState(() {
                        _pathway = value.first;
                        _onOsteoporosisTreatment =
                            _pathway == ClinicalPathway.pathway2;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Required clinical facts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _twoColumns(
                      TextFormField(
                        controller: _ageController,
                        decoration: const InputDecoration(labelText: 'Age'),
                        keyboardType: TextInputType.number,
                        validator: _numberRequired,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _sex,
                        decoration: const InputDecoration(labelText: 'Sex'),
                        items: const [
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('Female'),
                          ),
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                        ],
                        onChanged: (value) =>
                            setState(() => _sex = value ?? _sex),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _fractureSite,
                      decoration: const InputDecoration(
                        labelText: 'Fracture site',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'hip', child: Text('Hip')),
                        DropdownMenuItem(
                          value: 'vertebral',
                          child: Text('Vertebral'),
                        ),
                        DropdownMenuItem(value: 'wrist', child: Text('Wrist')),
                        DropdownMenuItem(
                          value: 'humerus',
                          child: Text('Humerus'),
                        ),
                        DropdownMenuItem(value: 'hand', child: Text('Hand')),
                        DropdownMenuItem(value: 'foot', child: Text('Foot')),
                        DropdownMenuItem(value: 'face', child: Text('Face')),
                        DropdownMenuItem(value: 'ankle', child: Text('Ankle')),
                      ],
                      onChanged: (value) => setState(
                        () => _fractureSite = value ?? _fractureSite,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SwitchRow(
                      label: 'Minimal trauma fracture',
                      value: _minimalTraumaFracture,
                      onChanged: (value) =>
                          setState(() => _minimalTraumaFracture = value),
                    ),
                    _SwitchRow(
                      label:
                          'Currently or previously on osteoporosis treatment',
                      value: _onOsteoporosisTreatment,
                      onChanged: (value) =>
                          setState(() => _onOsteoporosisTreatment = value),
                    ),
                    _SwitchRow(
                      label: 'Postmenopausal',
                      value: _postmenopausal,
                      onChanged: (value) =>
                          setState(() => _postmenopausal = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Investigations and risk flags',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _twoColumns(
                      TextFormField(
                        controller: _egfrController,
                        decoration: const InputDecoration(labelText: 'eGFR'),
                        keyboardType: TextInputType.number,
                        validator: _numberRequired,
                      ),
                      TextFormField(
                        controller: _tScoreController,
                        decoration: const InputDecoration(
                          labelText: 'Lowest T-score',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: _numberRequired,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _twoColumns(
                      TextFormField(
                        controller: _frailtyController,
                        decoration: const InputDecoration(
                          labelText: 'Clinical frailty score',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _numberRequired,
                      ),
                      TextFormField(
                        controller: _lifeExpectancyController,
                        decoration: const InputDecoration(
                          labelText: 'Life expectancy in years',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _numberRequired,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SwitchRow(
                      label: 'Lives in residential aged care',
                      value: _residentialCare,
                      onChanged: (value) =>
                          setState(() => _residentialCare = value),
                    ),
                    _SwitchRow(
                      label: 'Known poor medication adherence',
                      value: _poorAdherence,
                      onChanged: (value) =>
                          setState(() => _poorAdherence = value),
                    ),
                    _SwitchRow(
                      label: 'Cognitive impairment',
                      value: _cognitiveImpairment,
                      onChanged: (value) =>
                          setState(() => _cognitiveImpairment = value),
                    ),
                    _SwitchRow(
                      label: 'BMD DXA available',
                      value: _dxaAvailable,
                      onChanged: (value) =>
                          setState(() => _dxaAvailable = value),
                    ),
                    _SwitchRow(
                      label: 'DXA completed within last 2 years',
                      value: _dxaWithinTwoYears,
                      onChanged: _dxaAvailable
                          ? (value) =>
                              setState(() => _dxaWithinTwoYears = value)
                          : null,
                    ),
                    _SwitchRow(
                      label:
                          'Hip, vertebral, or 2+ fractures in last 24 months',
                      value: _majorRecentFracture,
                      onChanged: (value) =>
                          setState(() => _majorRecentFracture = value),
                    ),
                    _SwitchRow(
                      label: 'Very high fracture risk',
                      value: _highRisk,
                      onChanged: (value) => setState(() => _highRisk = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _evaluate,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rule),
              label: Text(_loading ? 'Evaluating' : 'Evaluate pathway'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _twoColumns(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Future<void> _evaluate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _loading = true);
    final clinicalCase = ClinicalCase(
      id: widget.existingCaseId ?? '',
      patientName: _patientNameController.text.trim(),
      pathway: _pathway,
      status: ClinicalCaseStatus.evaluated,
      facts: {
        'osteoporosisTreatmentStatus': _onOsteoporosisTreatment,
        'minimalTraumaFracture': _minimalTraumaFracture,
        'sex': _sex,
        'postmenopausal': _postmenopausal,
        'age': int.tryParse(_ageController.text),
        'fractureSite': _fractureSite,
        'eGFR': double.tryParse(_egfrController.text),
        'liveInResidentialCare': _residentialCare,
        'clinicalFrailtyScore': int.tryParse(_frailtyController.text),
        'lifeExpectancy': double.tryParse(_lifeExpectancyController.text),
        'knownPoorMedicationAdherence': _poorAdherence,
        'cognitiveImpairment': _cognitiveImpairment,
        'testAvailable': _dxaAvailable,
        'testWithinLast2Years': _dxaWithinTwoYears,
        'T-score': double.tryParse(_tScoreController.text),
        'hipVertebralOrMultipleFracturesInLast24M': _majorRecentFracture,
        'highRisk': _highRisk,
      },
    );
    final saved = await widget.repository.saveClinicalCase(clinicalCase);
    final evaluation = await widget.repository.evaluatePathway(saved);
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    widget.onEvaluationReady(saved, evaluation);
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _numberRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    if (double.tryParse(value) == null) {
      return 'Enter a number';
    }
    return null;
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
