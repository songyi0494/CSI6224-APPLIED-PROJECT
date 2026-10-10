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
  final List<QuestionnaireQuestion> _draftQuestions = [];
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
          : FutureBuilder<List<MockQuestionnaireDraft>>(
              key: ValueKey(_refreshKey),
              future: widget.repository.fetchMockQuestionnaireDrafts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Questionnaire builder persistence is BACKEND CONTRACT PENDING.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
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
                      onSaveDraft: () =>
                          _saveMockDraft(MockQuestionnaireDraftState.draft),
                      onMarkReady: () =>
                          _saveMockDraft(MockQuestionnaireDraftState.ready),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mock questionnaire drafts',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            if (questionnaires.isEmpty)
                              const EmptyState(
                                message: 'Create the first mock draft.',
                              )
                            else
                              for (final questionnaire in questionnaires)
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(questionnaire.displayTitle),
                                  subtitle: Text(
                                    '${mockQuestionnaireDraftStateLabel(questionnaire.state)} - '
                                    '${questionnaire.questions.length} questions',
                                  ),
                                  trailing:
                                      questionnaire.state ==
                                          MockQuestionnaireDraftState.ready
                                      ? null
                                      : Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  _loadQuestionnaire(
                                                    questionnaire,
                                                  ),
                                              child: const Text('Edit'),
                                            ),
                                            TextButton(
                                              onPressed: () => _markReady(
                                                questionnaire.presentationId,
                                              ),
                                              child: const Text('Mark ready'),
                                            ),
                                          ],
                                        ),
                                  children: [
                                    for (final question
                                        in questionnaire.questions)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.short_text),
                                        title: Text(question.questionText),
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
    final questionnaires = await widget.repository
        .fetchMockQuestionnaireDrafts();
    if (!mounted) {
      return;
    }
    for (final questionnaire in questionnaires) {
      if (questionnaire.presentationId == questionnaireId &&
          questionnaire.state == MockQuestionnaireDraftState.draft) {
        _loadQuestionnaire(questionnaire);
        break;
      }
    }
    setState(() => _loadingInitial = false);
  }

  void _loadQuestionnaire(MockQuestionnaireDraft questionnaire) {
    if (questionnaire.state != MockQuestionnaireDraftState.draft) {
      return;
    }
    setState(() {
      _draftId = questionnaire.presentationId;
      _titleController.text = questionnaire.displayTitle;
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
    if (_questionType.requiresOptions && options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choice questions need at least 2 options.'),
        ),
      );
      return;
    }
    _questionCounter++;
    setState(() {
      _draftQuestions.add(
        QuestionnaireQuestion(
          id: 'question-$_questionCounter',
          questionText: _promptController.text.trim(),
          type: _questionType,
          isRequired: _required,
          displayOrder: _draftQuestions.length + 1,
          options: options,
        ),
      );
      _promptController.clear();
      _optionsController.clear();
      _questionType = QuestionType.text;
      _required = true;
    });
  }

  void _removeQuestion(QuestionnaireQuestion question) {
    setState(() => _draftQuestions.remove(question));
  }

  int _highestQuestionIndex(List<QuestionnaireQuestion> questions) {
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

  Future<void> _saveMockDraft(MockQuestionnaireDraftState status) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_draftQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one question.')),
      );
      return;
    }
    final saved = await widget.repository.saveMockQuestionnaireDraft(
      MockQuestionnaireDraft(
        presentationId: _draftId ?? '',
        displayTitle: _titleController.text.trim(),
        state: status,
        questions: List<QuestionnaireQuestion>.unmodifiable(_draftQuestions),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftId = saved.presentationId;
      if (status == MockQuestionnaireDraftState.ready) {
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
          status == MockQuestionnaireDraftState.ready
              ? 'Mock questionnaire marked ready.'
              : 'Mock questionnaire saved as draft.',
        ),
      ),
    );
  }

  Future<void> _markReady(String questionnaireId) async {
    await widget.repository.markMockQuestionnaireDraftReady(questionnaireId);
    if (mounted) {
      setState(() => _refreshKey++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mock questionnaire marked ready.')),
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
    required this.onMarkReady,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final TextEditingController titleController;
  final TextEditingController promptController;
  final TextEditingController optionsController;
  final QuestionType questionType;
  final bool required;
  final List<QuestionnaireQuestion> questions;
  final ValueChanged<QuestionType> onQuestionTypeChanged;
  final ValueChanged<bool> onRequiredChanged;
  final VoidCallback onAddQuestion;
  final ValueChanged<QuestionnaireQuestion> onRemoveQuestion;
  final VoidCallback onSaveDraft;
  final VoidCallback onMarkReady;

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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
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
                          value: QuestionType.singleChoice,
                          child: Text('Single choice'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.numeric,
                          child: Text('Number'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.scale,
                          child: Text('Scale'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.dropdown,
                          child: Text('Dropdown'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.checkbox,
                          child: Text('Checkbox'),
                        ),
                        DropdownMenuItem(
                          value: QuestionType.multiChoice,
                          child: Text('Multiple choice'),
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
              if (questionType.requiresOptions) ...[
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
                    title: Text(question.questionText),
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
                    onPressed: onMarkReady,
                    icon: const Icon(Icons.publish_outlined),
                    label: const Text('Mark ready'),
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
