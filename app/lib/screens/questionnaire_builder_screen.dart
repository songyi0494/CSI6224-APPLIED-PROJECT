import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/questionnaire.dart';
import '../utils/display_labels.dart';
import '../widgets/empty_state.dart';

class QuestionnaireBuilderScreen extends StatefulWidget {
  const QuestionnaireBuilderScreen({
    required this.repository,
    this.initialQuestionnaireId,
    super.key,
  });

  final AppRepository repository;
  final String? initialQuestionnaireId;

  @override
  State<QuestionnaireBuilderScreen> createState() =>
      _QuestionnaireBuilderScreenState();
}

class _QuestionnaireBuilderScreenState
    extends State<QuestionnaireBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _optionsController = TextEditingController();
  final List<QuestionDefinition> _draftQuestions = [];
  QuestionType _questionType = QuestionType.text;
  bool _required = true;
  int _refreshKey = 0;
  int _questionCounter = 0;
  String? _draftId;
  bool _loadingInitial = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestionnaireId != null) {
      _loadInitialDraft(widget.initialQuestionnaireId!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questionnaire builder')),
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Questionnaire>>(
              key: ValueKey(_refreshKey),
              future: widget.repository.fetchQuestionnaires(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final questionnaires = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _BuilderCard(
                      formKey: _formKey,
                      titleController: _titleController,
                      promptController: _promptController,
                      optionsController: _optionsController,
                      questionType: _questionType,
                      required: _required,
                      questions: _draftQuestions,
                      title: _draftId == null
                          ? 'Create questionnaire'
                          : 'Edit draft questionnaire',
                      onQuestionTypeChanged: (value) =>
                          setState(() => _questionType = value),
                      onRequiredChanged: (value) =>
                          setState(() => _required = value),
                      onAddQuestion: _addQuestion,
                      onRemoveQuestion: _removeQuestion,
                      onSaveDraft: () => _saveQuestionnaire(
                        QuestionnaireStatus.draft,
                      ),
                      onPublish: () => _saveQuestionnaire(
                        QuestionnaireStatus.published,
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
                              'Current questionnaires',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            if (questionnaires.isEmpty)
                              const EmptyState(
                                message: 'Create the first questionnaire.',
                              )
                            else
                              for (final questionnaire in questionnaires)
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(questionnaire.title),
                                  subtitle: Text(
                                    '${questionnaireStatusLabel(questionnaire.status)} - '
                                    '${questionnaire.questions.length} questions',
                                  ),
                                  trailing: questionnaire.status ==
                                          QuestionnaireStatus.published
                                      ? null
                                      : Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  _loadQuestionnaire(
                                                      questionnaire),
                                              child: const Text('Edit'),
                                            ),
                                            TextButton(
                                              onPressed: () => _publishExisting(
                                                questionnaire.id,
                                              ),
                                              child: const Text('Publish'),
                                            ),
                                          ],
                                        ),
                                  children: [
                                    for (final question
                                        in questionnaire.questions)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.short_text),
                                        title: Text(question.prompt),
                                        subtitle: Text(
                                          questionTypeLabel(question.type),
                                        ),
                                      ),
                                  ],
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _loadInitialDraft(String questionnaireId) async {
    setState(() => _loadingInitial = true);
    final questionnaires = await widget.repository.fetchQuestionnaires();
    if (!mounted) {
      return;
    }
    for (final questionnaire in questionnaires) {
      if (questionnaire.id == questionnaireId &&
          questionnaire.status == QuestionnaireStatus.draft) {
        _loadQuestionnaire(questionnaire);
        break;
      }
    }
    setState(() => _loadingInitial = false);
  }

  void _loadQuestionnaire(Questionnaire questionnaire) {
    if (questionnaire.status != QuestionnaireStatus.draft) {
      return;
    }
    setState(() {
      _draftId = questionnaire.id;
      _titleController.text = questionnaire.title;
      _draftQuestions
        ..clear()
        ..addAll(questionnaire.questions);
      _questionCounter = _highestQuestionIndex(questionnaire.questions);
    });
  }

  void _addQuestion() {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a question prompt first.')),
      );
      return;
    }
    final options = _optionsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (_questionType == QuestionType.choice && options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choice questions need at least 2 options.')),
      );
      return;
    }
    _questionCounter++;
    setState(() {
      _draftQuestions.add(
        QuestionDefinition(
          id: 'question-$_questionCounter',
          prompt: _promptController.text.trim(),
          type: _questionType,
          required: _required,
          options: options,
        ),
      );
      _promptController.clear();
      _optionsController.clear();
      _questionType = QuestionType.text;
      _required = true;
    });
  }

  void _removeQuestion(QuestionDefinition question) {
    setState(() => _draftQuestions.remove(question));
  }

  int _highestQuestionIndex(List<QuestionDefinition> questions) {
    var highest = 0;
    final pattern = RegExp(r'^question-(\d+)$');
    for (final question in questions) {
      final match = pattern.firstMatch(question.id);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > highest) {
        highest = value;
      }
    }
    return highest;
  }

  Future<void> _saveQuestionnaire(QuestionnaireStatus status) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_draftQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one question.')),
      );
      return;
    }
    final saved = await widget.repository.saveQuestionnaire(
      Questionnaire(
        id: _draftId ?? '',
        title: _titleController.text.trim(),
        status: status,
        questions: List<QuestionDefinition>.unmodifiable(_draftQuestions),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftId = saved.id;
      if (status == QuestionnaireStatus.published) {
        _titleController.clear();
        _draftQuestions.clear();
        _questionCounter = 0;
        _draftId = null;
      }
      _refreshKey++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == QuestionnaireStatus.published
              ? 'Questionnaire published.'
              : 'Questionnaire saved as draft.',
        ),
      ),
    );
  }

  Future<void> _publishExisting(String questionnaireId) async {
    await widget.repository.publishQuestionnaire(questionnaireId);
    if (mounted) {
      setState(() => _refreshKey++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questionnaire published.')),
      );
    }
  }
}

class _BuilderCard extends StatelessWidget {
  const _BuilderCard({
    required this.formKey,
    required this.title,
    required this.titleController,
    required this.promptController,
    required this.optionsController,
    required this.questionType,
    required this.required,
    required this.questions,
    required this.onQuestionTypeChanged,
    required this.onRequiredChanged,
    required this.onAddQuestion,
    required this.onRemoveQuestion,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final TextEditingController titleController;
  final TextEditingController promptController;
  final TextEditingController optionsController;
  final QuestionType questionType;
  final bool required;
  final List<QuestionDefinition> questions;
  final ValueChanged<QuestionType> onQuestionTypeChanged;
  final ValueChanged<bool> onRequiredChanged;
  final VoidCallback onAddQuestion;
  final ValueChanged<QuestionDefinition> onRemoveQuestion;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Text(
                'New question',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                decoration: const InputDecoration(labelText: 'Prompt'),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final fields = [
                    DropdownButtonFormField<QuestionType>(
                      initialValue: questionType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                          value: QuestionType.text,
                          child: Text('Text'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.yesNo,
                          child: Text('Yes / No'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.number,
                          child: Text('Number'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.scale,
                          child: Text('Scale'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.choice,
                          child: Text('Choice'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onQuestionTypeChanged(value);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Required'),
                      value: required,
                      onChanged: onRequiredChanged,
                    ),
                  ];
                  if (compact) {
                    return Column(
                      children: [
                        fields.first,
                        const SizedBox(height: 12),
                        fields.last,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: fields.first),
                      const SizedBox(width: 12),
                      Expanded(child: fields.last),
                    ],
                  );
                },
              ),
              if (questionType == QuestionType.choice) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: optionsController,
                  decoration: const InputDecoration(
                    labelText: 'Options separated by commas',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAddQuestion,
                icon: const Icon(Icons.add),
                label: const Text('Add question'),
              ),
              const SizedBox(height: 16),
              if (questions.isEmpty)
                const EmptyState(message: 'No questions added yet.')
              else
                for (final question in questions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.short_text),
                    title: Text(question.prompt),
                    subtitle: Text(questionTypeLabel(question.type)),
                    trailing: IconButton(
                      tooltip: 'Remove question',
                      onPressed: () => onRemoveQuestion(question),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: onSaveDraft,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                  FilledButton.icon(
                    onPressed: onPublish,
                    icon: const Icon(Icons.publish_outlined),
                    label: const Text('Publish'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
