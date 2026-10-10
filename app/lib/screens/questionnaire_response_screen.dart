import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../models/questionnaire.dart';

class QuestionnaireResponseScreen extends StatefulWidget {
  const QuestionnaireResponseScreen({
    required this.form,
    required this.repository,
    required this.profileSexAtBirth,
    this.initialAnswers = const {},
    super.key,
  });

  final QuestionnaireForm form;
  final AppRepository repository;
  final String? profileSexAtBirth;
  final Map<String, Object?> initialAnswers;

  @override
  State<QuestionnaireResponseScreen> createState() =>
      _QuestionnaireResponseScreenState();
}

class _QuestionnaireResponseScreenState
    extends State<QuestionnaireResponseScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _textControllers = {};
  late final Map<String, Object?> _answers;
  bool _submitting = false;

  List<QuestionnaireQuestion> get _patientQuestions => widget
      .form
      .orderedQuestions
      .where((question) => question.fieldKey != 'sex')
      .toList(growable: false);

  bool get _profileIsFemale =>
      normalizeSexRecordedAtBirth(widget.profileSexAtBirth) == 'female';

  List<QuestionnaireQuestion> get _visibleQuestions => _patientQuestions
      .where(
        (question) => question.fieldKey == 'postmenopausal'
            ? _profileIsFemale
            : question.isVisible(_answers),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _answers = Map<String, Object?>.from(widget.initialAnswers);
    // Sex is profile-derived and never editable in the questionnaire.
    _answers.remove('sex');
    if (!_profileIsFemale) _answers.remove('postmenopausal');
    for (final question in _patientQuestions) {
      if (question.type == QuestionType.text ||
          question.type == QuestionType.numeric ||
          question.type == QuestionType.scale) {
        final initialValue = _answers[question.mockUiAnswerKey];
        _textControllers[question.mockUiAnswerKey] = TextEditingController(
          text: initialValue?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaire')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  widget.form.displayTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Patient reported • Your clinician will review this information before using it as a confirmed clinical fact.',
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value:
                  _answeredVisibleCount /
                  (_visibleQuestions.isEmpty ? 1 : _visibleQuestions.length),
            ),
            const SizedBox(height: 16),
            for (final section in _sections) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final question in _visibleQuestions.where(
                        (q) => q.section == section,
                      )) ...[
                        _QuestionInput(
                          question: question,
                          controller:
                              _textControllers[question.mockUiAnswerKey],
                          value: _answers[question.mockUiAnswerKey],
                          onChanged: (value) =>
                              _handleAnswerChanged(question, value),
                          showPersistencePending: false,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _review,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review your answers'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _sections => _visibleQuestions
      .map((question) => question.section)
      .toSet()
      .toList(growable: false);

  int get _answeredVisibleCount => _visibleQuestions.where((question) {
    final controller = _textControllers[question.mockUiAnswerKey];
    return controller != null
        ? controller.text.trim().isNotEmpty
        : _answers[question.mockUiAnswerKey] != null;
  }).length;

  void _handleAnswerChanged(QuestionnaireQuestion question, Object? value) {
    setState(() {
      _answers[question.mockUiAnswerKey] = value;
      for (final candidate in _patientQuestions) {
        final visible = candidate.fieldKey == 'postmenopausal'
            ? _profileIsFemale
            : candidate.isVisible(_answers);
        if (!visible) {
          _answers.remove(candidate.mockUiAnswerKey);
          _textControllers[candidate.mockUiAnswerKey]?.clear();
        }
      }
    });
  }

  Future<void> _review() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review your answers'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Please check this patient-reported information before submitting.',
              ),
              const SizedBox(height: 12),
              for (final question in _visibleQuestions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(question.questionText),
                  subtitle: Text(_displayAnswer(question)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back to edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit questionnaire'),
          ),
        ],
      ),
    );
    if (proceed == true) await _submit();
  }

  String _displayAnswer(QuestionnaireQuestion question) {
    final controller = _textControllers[question.mockUiAnswerKey];
    return controller?.text.trim() ??
        _answers[question.mockUiAnswerKey]?.toString() ??
        'Not provided';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final answers = <String, Object?>{};
    for (final question in _visibleQuestions) {
      final answerKey = question.productionAnswerKey;
      Object? value;

      if (_textControllers.containsKey(question.mockUiAnswerKey)) {
        final rawValue =
            _textControllers[question.mockUiAnswerKey]!.text.trim();

        if (rawValue.isEmpty) continue;

        value = question.type == QuestionType.numeric ||
                question.type == QuestionType.scale
            ? num.tryParse(rawValue)
            : rawValue;
      } else {
        value = _answers[question.mockUiAnswerKey];

        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        if (value is List && value.isEmpty) continue;
      }

      if (value != null) {
        answers[answerKey] = value;
      }
    }

    setState(() => _submitting = true);
    try {
      final response = await widget.repository.submitQuestionnaireResponse(
        answers: answers,
      );
      if (!mounted) {
        return;
      }
      if (response.pathwayEligible == false) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Pathway Eligibility'),
            content: const Text(
              'You do not meet the entry criteria for this osteoporosis '
              'treatment pathway. Please consult your healthcare '
              'professional for further advice.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Questionnaire submitted.')),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(response);
    } on AppException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _QuestionInput extends StatelessWidget {
  const _QuestionInput({
    required this.question,
    required this.controller,
    required this.value,
    required this.onChanged,
    required this.showPersistencePending,
  });

  final QuestionnaireQuestion question;
  final TextEditingController? controller;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool showPersistencePending;

  @override
  Widget build(BuildContext context) {
    late final Widget input;
    switch (question.type) {
      case QuestionType.singleChoice:
      case QuestionType.dropdown:
        input = DropdownButtonFormField<String>(
          initialValue: value as String?,
          decoration: InputDecoration(labelText: question.questionText),
          items: [
            for (final option in question.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
          validator: (value) =>
              question.isRequired && (value == null || value.trim().isEmpty)
              ? 'Required'
              : null,
        );
        break;
      case QuestionType.numeric:
      case QuestionType.scale:
        input = TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: question.questionText),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (question.isRequired &&
                (value == null || value.trim().isEmpty)) {
              return 'Required';
            }
            if (value != null &&
                value.trim().isNotEmpty &&
                num.tryParse(value) == null) {
              return 'Enter a number';
            }
            return null;
          },
        );
        break;
      case QuestionType.checkbox:
        input = FormField<bool>(
          initialValue: value as bool?,
          validator: (value) =>
              question.isRequired && value == null ? 'Required' : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(question.questionText),
                tristate: true,
                value: field.value,
                onChanged: (value) {
                  field.didChange(value);
                  onChanged(value);
                },
              ),
              if (field.hasError)
                Text(
                  field.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        );
        break;
      case QuestionType.multiChoice:
        input = FormField<List<String>>(
          validator: (_) =>
              'Multiple-choice input is not supported in this UI yet.',
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.questionText,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                field.errorText ??
                    'Multiple-choice input is not supported in this UI yet.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        );
        break;
      case QuestionType.text:
        input = TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: question.questionText),
          maxLines: 3,
          validator: (value) =>
              question.isRequired && (value == null || value.trim().isEmpty)
              ? 'Required'
              : null,
        );
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        input,
        if (question.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            question.helperText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (showPersistencePending) ...[
          const SizedBox(height: 4),
          Text(
            'Shown in this questionnaire; production persistence is pending.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
