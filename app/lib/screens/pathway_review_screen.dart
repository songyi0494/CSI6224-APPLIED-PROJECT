import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/clinical_input.dart';
import '../utils/clinical_labels.dart';

class PathwayReviewScreen extends StatefulWidget {
  const PathwayReviewScreen({
    required this.repository,
    required this.id,
    required this.revision,
    required this.input,
    super.key,
  });

  final AppRepository repository;
  final String id;
  final int revision;
  final ClinicalInput input;

  @override
  State<PathwayReviewScreen> createState() => _PathwayReviewScreenState();
}

class _PathwayReviewScreenState extends State<PathwayReviewScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _confirmSubmit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.submitAssessment(
        id: widget.id,
        revision: widget.revision,
        input: widget.input,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Assessment submitted. A clinician will review your information.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is AppException
            ? e.message
            : 'We could not submit your assessment. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review your assessment')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Please check your answers before submitting.'),
                const SizedBox(height: 20),
                _section('Treatment history', [
                  _answer(
                    'Have you ever taken medicine for osteoporosis?',
                    factText(widget.input.treated),
                  ),
                ]),
                _section('Health information', [
                  _answer(
                    'Sex at birth',
                    sexAtBirthText(widget.input.sexAtBirth),
                  ),
                  if (widget.input.sexAtBirth == 'female')
                    _answer(
                      clinicalLabel('postmenopausal'),
                      factText(widget.input.postmenopausal),
                    ),
                ]),
                _section('Fracture history', [
                  _answer(
                    clinicalLabel('minimalTraumaFracture'),
                    factText(widget.input.minimalTraumaFracture),
                  ),
                  if (widget.input.minimalTraumaFracture == true ||
                      widget.input.fractureSite != null)
                    _answer(
                      clinicalLabel('fractureSite'),
                      fractureSiteText(widget.input.fractureSite),
                    ),
                ]),
                _section('Living situation', [
                  _answer(
                    clinicalLabel('liveInResidentialCare'),
                    factText(widget.input.residentialCare),
                  ),
                ]),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'You can withdraw and edit your assessment until a clinician starts reviewing it. Once clinical review has started, contact your clinician if information needs to be corrected.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Back and edit'),
                    ),
                    FilledButton(
                      onPressed: _submitting ? null : _confirmSubmit,
                      child: Text(
                        _submitting ? 'Submitting...' : 'Confirm & submit',
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

  Widget _answer(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
