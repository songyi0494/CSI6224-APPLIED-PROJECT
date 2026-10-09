import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/questionnaire.dart';

class ManageQuestionnaireScreen extends StatefulWidget {
  const ManageQuestionnaireScreen({
    super.key,
    required this.repository,
  });
  
  final AppRepository repository;

  @override
  State<ManageQuestionnaireScreen> createState() => 
    _ManageQuestionnaireScreenState();
}

class _ManageQuestionnaireScreenState
  extends State<ManageQuestionnaireScreen> {
    late Future<QuestionnaireForm> _formFuture;

    @override
    void initState() {
      super.initState();
      _loadQuestions();
    }

    void _loadQuestions() {
      _formFuture = widget.repository.fetchQuestionnaireForm();
    }

    void _refreshQuestions() {
      setState(() {
        _loadQuestions();
      });
    }
    
    Future<void> _showAddQuestionDialog() async {
      final textController = TextEditingController();
      final optionsController = TextEditingController();

      QuestionType selectedType = QuestionType.text;
      bool isRequired = true;
      bool isSaving = false;

      try {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Add Question'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: textController,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<QuestionType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Question Type',
                        ),
                        items: QuestionType.values
                            .where((type) => type != QuestionType.multiChoice)
                            .map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.databaseValue),
                          );
                        }).toList(),
                        onChanged: isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedType = value;
                                  });
                                }
                              },
                      ),
                      if (selectedType.requiresOptions) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: optionsController,
                          decoration: const InputDecoration(
                            labelText: 'Options (comma separated)',
                            hintText: 'Yes, No',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        title: const Text('Required question'),
                        value: isRequired,
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  isRequired = value ?? false;
                                });
                              },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final questionText = textController.text.trim();

                            final options = selectedType.requiresOptions
                                ? optionsController.text
                                    .split(',')
                                    .map((option) => option.trim())
                                    .where((option) => option.isNotEmpty)
                                    .toList()
                                : <String>[];

                            if (questionText.isEmpty) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a question.'),
                                ),
                              );
                              return;
                            }

                            if (selectedType.requiresOptions &&
                                options.length < 2) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter at least two options.'),
                                ),
                              );
                              return;
                            }

                            setDialogState(() {
                              isSaving = true;
                            });

                            try {
                              await widget.repository.createQuestionnaireQuestion(
                                questionText: questionText,
                                type: selectedType,
                                options: options,
                                isRequired: isRequired,
                              );

                              if (!mounted) return;

                              Navigator.pop(dialogContext);
                              _refreshQuestions();

                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Question added successfully.'),
                                ),
                              );
                            } catch (error) {
                              if (!mounted) return;

                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );

                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          },
                    child: Text(isSaving ? 'Saving...' : 'Save'),
                  ),
                ],
              );
            },
          ),
        );
      } finally {
        // Controllers are released after the dialog finishes closing.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        textController.dispose();
        optionsController.dispose();
      }
    }

    // Edit function
    Future<void> _showEditQuestionDialog(
      QuestionnaireQuestion question,
    ) async {
      final textController = TextEditingController(
        text: question.questionText,
      );
      final optionsController = TextEditingController(
        text: question.options.join(', '),
      );

      QuestionType selectedType = question.type;
      bool isRequired = question.isRequired;
      bool isSaving = false;

      try {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Edit Question'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      decoration: const InputDecoration(
                        labelText: 'Question',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<QuestionType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Question Type',
                      ),
                      items: QuestionType.values
                          .where((type) => type != QuestionType.multiChoice)
                          .map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.databaseValue),
                        );
                      }).toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedType = value;
                                });
                              }
                            },
                    ),
                    if (selectedType.requiresOptions) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: optionsController,
                        decoration: const InputDecoration(
                          labelText: 'Options (comma separated)',
                          hintText: 'Yes, No',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Required question'),
                      value: isRequired,
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setDialogState(() {
                                isRequired = value ?? false;
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final questionText = textController.text.trim();

                          final options = selectedType.requiresOptions
                              ? optionsController.text
                                  .split(',')
                                  .map((option) => option.trim())
                                  .where((option) => option.isNotEmpty)
                                  .toList()
                              : <String>[];

                          if (questionText.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a question.'),
                              ),
                            );
                            return;
                          }

                          if (selectedType.requiresOptions &&
                              options.length < 2) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter at least two options.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await widget.repository.updateQuestionnaireQuestion(
                                QuestionnaireQuestion(
                                  id: question.id,
                                  fieldKey: question.fieldKey,
                                  questionText: questionText,
                                  type: selectedType,
                                  options: options,
                                  isRequired: isRequired,
                                  displayOrder: question.displayOrder,
                                  createdBy: question.createdBy,
                                ),
                            );

                            if (!mounted) return;

                            Navigator.pop(dialogContext);
                            _refreshQuestions();

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Question updated successfully.'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) return;

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );

                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: Text(isSaving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
          ),
        );
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        textController.dispose();
        optionsController.dispose();
      }
    }

    // delete function
    Future<void> _deleteQuestion(
      QuestionnaireQuestion question,
    ) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Question'),
          content: Text(
            'Are you sure you want to delete this question?\n\n'
            '${question.questionText}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      try {
        await widget.repository.deleteQuestionnaireQuestion(question.id);

        if (!mounted) return;

        _refreshQuestions();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Question deleted successfully.'),
          ),
        );
      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }

    @override
    Widget build(BuildContext contest) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Questionnaire'),
        ),
        body: FutureBuilder<QuestionnaireForm>(
          future: _formFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load questions'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _refreshQuestions,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

          final questions = snapshot.data!.orderedQuestions;

          final systemQuestions = questions
              .where((question) => question.isSystemQuestion)
              .toList();

          final customQuestions = questions
              .where((question) => !question.isSystemQuestion)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'System Questions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...systemQuestions.map(
                (question) => ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(question.questionText),
                  subtitle: Text(question.type.databaseValue),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Additional Questions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (customQuestions.isEmpty)
                const ListTile(
                  title: Text('No additional questions yet.'),
                ),
              ...customQuestions.map(
                (question) => ListTile(
                  title: Text(question.questionText),
                  subtitle: Text(question.type.databaseValue),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit question',
                        onPressed: () => _showEditQuestionDialog(question),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete question',
                        onPressed: () => _deleteQuestion(question),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showAddQuestionDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Question'),
              ),
            ],
          );
        },
      ),
    );
  }
}
