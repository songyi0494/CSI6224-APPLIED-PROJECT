import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/questionnaire.dart';

class QuestionnaireResponseScreen extends StatefulWidget {
  const QuestionnaireResponseScreen({
    required this.questionnaire,
    required this.repository,
    required this.patientName,
    super.key,
  });

  final Questionnaire questionnaire;
  final AppRepository repository;
  final String patientName;

  @override
  State<QuestionnaireResponseScreen> createState() =>
      _QuestionnaireResponseScreenState();
}

class _QuestionnaireResponseScreenState
    extends State<QuestionnaireResponseScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, Object?> _answers = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final question in widget.questionnaire.questions) {
      if (question.type == QuestionType.text ||
          question.type == QuestionType.number ||
          question.type == QuestionType.scale) {
        _textControllers[question.id] = TextEditingController();
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.questionnaire.title,
                      style: Theme.of(context).textTheme.titleLarge,
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
                    for (final question in widget.questionnaire.questions) ...[
                      _QuestionInput(
                        question: question,
                        controller: _textControllers[question.id],
                        value: _answers[question.id],
                        onChanged: (value) =>
                            setState(() => _answers[question.id] = value),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(_submitting ? 'Submitting' : 'Submit'),
                      ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final answers = <String, Object?>{};
    for (final question in widget.questionnaire.questions) {
      if (_textControllers.containsKey(question.id)) {
        final rawValue = _textControllers[question.id]!.text.trim();
        answers[question.id] = question.type == QuestionType.number ||
                question.type == QuestionType.scale
            ? num.tryParse(rawValue)
            : rawValue;
      } else {
        answers[question.id] = _answers[question.id];
      }
    }

    setState(() => _submitting = true);
    await widget.repository.submitPatientResponse(
      questionnaireId: widget.questionnaire.id,
      patientName: widget.patientName,
      answers: answers,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Questionnaire submitted.')),
    );
    Navigator.of(context).pop();
  }
}

class _QuestionInput extends StatelessWidget {
  const _QuestionInput({
    required this.question,
    required this.controller,
    required this.value,
    required this.onChanged,
  });

  final QuestionDefinition question;
  final TextEditingController? controller;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.yesNo:
        return FormField<bool>(
          initialValue: value is bool ? value as bool : null,
          validator: (value) =>
              question.required && value == null ? 'Required' : null,
          builder: (field) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QuestionLabel(question: question),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Yes')),
                    ButtonSegment(value: false, label: Text('No')),
                  ],
                  selected: field.value == null
                      ? const <bool>{}
                      : <bool>{field.value!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (selection) {
                    final nextValue =
                        selection.isEmpty ? null : selection.first;
                    field.didChange(nextValue);
                    onChanged(nextValue);
                  },
                ),
                if (field.hasError) ...[
                  const SizedBox(height: 6),
                  Text(
                    field.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      case QuestionType.choice:
        return DropdownButtonFormField<String>(
          initialValue: value as String?,
          decoration: InputDecoration(labelText: question.prompt),
          items: [
            for (final option in question.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
          validator: (value) =>
              question.required && (value == null || value.trim().isEmpty)
                  ? 'Required'
                  : null,
        );
      case QuestionType.number:
      case QuestionType.scale:
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: question.prompt),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (question.required && (value == null || value.trim().isEmpty)) {
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
      case QuestionType.text:
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: question.prompt),
          maxLines: 3,
          validator: (value) =>
              question.required && (value == null || value.trim().isEmpty)
                  ? 'Required'
                  : null,
        );
    }
  }
}

class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel({required this.question});

  final QuestionDefinition question;

  @override
  Widget build(BuildContext context) {
    return Text(
      question.prompt,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}
