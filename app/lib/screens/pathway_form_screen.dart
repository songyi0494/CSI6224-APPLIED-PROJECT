import 'package:flutter/material.dart';
import '../utils/new_id.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../utils/clinical_labels.dart';

class PathwayFormScreen extends StatefulWidget {
  const PathwayFormScreen({
    required this.repository,
    required this.user,
    this.assessment,
    super.key,
  });
  final AppRepository repository;
  final AppUser user;
  final ClinicalCase? assessment;
  @override
  State<PathwayFormScreen> createState() => _PathwayFormScreenState();
}

class _PathwayFormScreenState extends State<PathwayFormScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _numbers = {};
  final Map<String, Object?> _answers = {};
  late String _id;
  late int _revision;
  bool _saving = false;
  String? _error;
  static const _numeric = [
    'age',
    'eGFR',
    'clinicalFrailtyScore',
    'lifeExpectancy',
    'T-score',
    'vitaminDLevel',
    'yearSincePostmenopausal',
  ];
  @override
  void initState() {
    super.initState();
    _id = widget.assessment?.id ?? newId();
    _revision = widget.assessment?.revision ?? 0;
    _answers.addAll(widget.assessment?.input.toFacts() ?? {});
    if (widget.assessment == null) {
      _answers['sex'] = widget.user.sexAtBirth;
      final birth = widget.user.dateOfBirth;
      if (birth != null) {
        final now = DateTime.now();
        _answers['age'] =
            now.year -
            birth.year -
            ((now.month < birth.month ||
                    (now.month == birth.month && now.day < birth.day))
                ? 1
                : 0);
      }
    }
    for (final key in _numeric) {
      _numbers[key] = TextEditingController(
        text: _answers[key]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool submit) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final facts = Map<String, Object?>.from(_answers);
      for (final key in _numeric) {
        final raw = _numbers[key]!.text.trim();
        facts[key] = raw.isEmpty
            ? null
            : (key == 'age' || key == 'clinicalFrailtyScore'
                  ? int.parse(raw)
                  : double.parse(raw));
      }
      final input = ClinicalInput.fromFacts(facts);
      final result = submit
          ? await widget.repository.submitAssessment(
              id: _id,
              revision: _revision,
              input: input,
            )
          : await widget.repository.saveAssessment(
              id: _id,
              revision: _revision,
              input: input,
            );
      _revision = result.revision;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submit
                ? 'Assessment submitted. A clinician will review your information.'
                : 'Assessment saved.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'We could not save your assessment. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _number(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _numbers[key],
      decoration: InputDecoration(
        labelText: clinicalLabel(key),
        hintText: 'Leave blank if not provided',
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: key != 'age' && key != 'clinicalFrailtyScore',
        signed: key == 'T-score',
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final n = double.tryParse(v);
        if (n == null || !n.isFinite) return 'Enter a valid number';
        if ((key == 'age' || key == 'clinicalFrailtyScore') &&
            int.tryParse(v) == null)
          return 'Enter a whole number';
        if (key != 'T-score' && n < 0) return 'Enter zero or a positive number';
        return null;
      },
    ),
  );
  Widget _boolean(String key, {String? label}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: _answers[key] == null
          ? 'unknown'
          : _answers[key] == true
          ? 'yes'
          : 'no',
      decoration: InputDecoration(labelText: label ?? clinicalLabel(key)),
      isExpanded: true,
      items: const [
        DropdownMenuItem(
          value: 'unknown',
          child: Text('Not sure / not provided'),
        ),
        DropdownMenuItem(value: 'yes', child: Text('Yes')),
        DropdownMenuItem(value: 'no', child: Text('No')),
      ],
      onChanged: (v) => setState(
        () => _answers[key] = v == 'yes'
            ? true
            : v == 'no'
            ? false
            : null,
      ),
    ),
  );
  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your assessment')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tell us what you know. Leave information blank if you do not have it. Your clinician can ask for more information.',
                  ),
                  const SizedBox(height: 20),
                  if (widget.assessment?.decisionNotes != null)
                    _section('Information requested', [
                      Text(widget.assessment!.decisionNotes!),
                    ]),
                  _section('Treatment history', [
                    _boolean(
                      'osteoporosisTreatmentStatus',
                      label: 'Have you ever taken medicine for osteoporosis?',
                    ),
                  ]),
                  _section('Health information', [
                    _number('age'),
                    DropdownButtonFormField<String>(
                      initialValue: _answers['sex'] as String?,
                      decoration: const InputDecoration(
                        labelText: 'Sex at birth',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Another recorded sex'),
                        ),
                        DropdownMenuItem(
                          value: 'not_provided',
                          child: Text('Prefer not to say'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _answers['sex'] = v),
                    ),
                    const SizedBox(height: 16),
                    if (_answers['sex'] == 'female') ...[
                      _boolean('postmenopausal'),
                      _number('yearSincePostmenopausal'),
                    ],
                  ]),
                  _section('Fracture history', [
                    _boolean('minimalTraumaFracture'),
                    DropdownButtonFormField<String>(
                      initialValue: _answers['fractureSite'] as String?,
                      decoration: const InputDecoration(
                        labelText: 'Fracture site',
                      ),
                      items: [
                        for (final site in [
                          'hip',
                          'vertebral',
                          'wrist',
                          'humerus',
                          'hand',
                          'foot',
                          'face',
                          'ankle',
                        ])
                          DropdownMenuItem(
                            value: site,
                            child: Text(
                              site == 'vertebral'
                                  ? 'Spine'
                                  : site[0].toUpperCase() + site.substring(1),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _answers['fractureSite'] = v),
                    ),
                    const SizedBox(height: 16),
                    _boolean('hipVertebralOrMultipleFracturesInLast24M'),
                  ]),
                  _section('Bone health', [
                    _boolean('testAvailable'),
                    if (_answers['testAvailable'] == true) ...[
                      _boolean('testWithinLast2Years'),
                      _number('T-score'),
                    ],
                    _number('eGFR'),
                    _number('vitaminDLevel'),
                    const Text(
                      'Use values from your clinical records. eGFR and creatinine clearance are different measurements. Do not substitute one for the other.',
                    ),
                  ]),
                  _section('Care and current medicines', [
                    _boolean('liveInResidentialCare'),
                    _boolean('knownPoorMedicationAdherence'),
                    _boolean('cognitiveImpairment'),
                    _boolean('historyOfMiOrStroke'),
                    _boolean('highRisk'),
                    _number('clinicalFrailtyScore'),
                    _number('lifeExpectancy'),
                  ]),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : () => _save(false),
                        child: const Text('Save draft'),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : () => _save(true),
                        child: Text(
                          _saving ? 'Saving...' : 'Submit assessment',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
