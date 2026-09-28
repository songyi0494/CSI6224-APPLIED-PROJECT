import 'package:flutter/material.dart';
import '../utils/new_id.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/clinical_case.dart';
import '../models/clinical_input.dart';
import '../utils/clinical_labels.dart';
import 'pathway_review_screen.dart';

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
  static const _numeric = <String>[];
  @override
  void initState() {
    super.initState();
    _id = widget.assessment?.id ?? newId();
    _revision = widget.assessment?.revision ?? 0;
    _answers.addAll(widget.assessment?.input.toFacts() ?? {});
    if (widget.assessment == null) {
      _answers['sex'] = widget.user.sexAtBirth;
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

  ClinicalInput _buildInput() {
    final facts = Map<String, Object?>.from(_answers);
    for (final key in _numeric) {
      final raw = _numbers[key]!.text.trim();
      facts[key] = raw.isEmpty
          ? null
          : (key == 'clinicalFrailtyScore'
                ? int.parse(raw)
                : double.parse(raw));
    }
    facts['age'] = _derivedAge();
    for (final key in _clinicianOwnedFactKeys) {
      facts.remove(key);
    }
    return ClinicalInput.fromFacts(facts);
  }

  Future<void> _saveDraft() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.saveAssessment(
        id: _id,
        revision: _revision,
        input: _buildInput(),
      );
      _revision = result.revision;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assessment saved.')),
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

  Future<void> _reviewAnswers() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      final submitted = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => PathwayReviewScreen(
            repository: widget.repository,
            id: _id,
            revision: _revision,
            input: _buildInput(),
          ),
        ),
      );
      if (submitted == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'We could not prepare your review. Please try again.',
        );
    }
  }

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
                            child: Text(fractureSiteText(site)),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _answers['fractureSite'] = v),
                    ),
                    const SizedBox(height: 16),
                  ]),
                  _section('Living situation', [
                    _boolean('liveInResidentialCare'),
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
                        onPressed: _saving ? null : _saveDraft,
                        child: const Text('Save draft'),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _reviewAnswers,
                        child: Text(
                          _saving ? 'Saving...' : 'Review answers',
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

  int? _derivedAge() {
    final birth = widget.user.dateOfBirth;
    if (birth == null) return null;
    final now = DateTime.now();
    return now.year -
        birth.year -
        ((now.month < birth.month ||
                (now.month == birth.month && now.day < birth.day))
            ? 1
            : 0);
  }

  static const _clinicianOwnedFactKeys = {
    'eGFR',
    'clinicalFrailtyScore',
    'lifeExpectancy',
    'knownPoorMedicationAdherence',
    'cognitiveImpairment',
    'testAvailable',
    'testWithinLast2Years',
    'T-score',
    'vitaminDLevel',
    'hipVertebralOrMultipleFracturesInLast24M',
    'highRisk',
    'historyOfMiOrStroke',
    'yearSincePostmenopausal',
    'isRobustWoman',
  };
}
