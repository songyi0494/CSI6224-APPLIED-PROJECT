import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/case_investigations.dart';

class InvestigationsScreen extends StatefulWidget {
  const InvestigationsScreen({
    required this.repository,
    required this.investigations,
    super.key,
  });

  final AppRepository repository;
  final CaseInvestigations investigations;

  @override
  State<InvestigationsScreen> createState() => _InvestigationsScreenState();
}

class _InvestigationsScreenState extends State<InvestigationsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vitaminD;
  late final TextEditingController _ionisedCalcium;
  late final TextEditingController _bodyWeight;
  late CaseInvestigations _current;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.investigations;
    _vitaminD = TextEditingController();
    _ionisedCalcium = TextEditingController();
    _bodyWeight = TextEditingController();
    _populate(_current);
  }

  @override
  void dispose() {
    _vitaminD.dispose();
    _ionisedCalcium.dispose();
    _bodyWeight.dispose();
    super.dispose();
  }

  void _populate(CaseInvestigations value) {
    _vitaminD.text = _display(value.vitaminDLevel);
    _ionisedCalcium.text = _display(value.ionisedCalcium);
    _bodyWeight.text = _display(value.bodyWeightKg);
  }

  String _display(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  String? _validateNumber(String? value, {required bool allowZero}) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Required';
    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) return 'Enter a valid number';
    if (allowZero ? parsed < 0 : parsed <= 0) {
      return allowZero
          ? 'Enter zero or a positive number'
          : 'Enter a value above zero';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveCaseInvestigations(
        caseId: _current.caseId,
        vitaminDLevel: double.parse(_vitaminD.text.trim()),
        ionisedCalcium: double.parse(_ionisedCalcium.text.trim()),
        bodyWeightKg: double.parse(_bodyWeight.text.trim()),
        expectedRevision: _current.revision,
      );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } on InvestigationConflictException catch (error) {
      try {
        final latest = await widget.repository.getCaseInvestigations(
          _current.caseId,
        );
        if (!mounted) return;
        setState(() {
          _current = latest;
          _populate(latest);
          _error = error.message;
        });
      } on AppException catch (reloadError) {
        if (mounted) setState(() => _error = reloadError.message);
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The investigation values could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Investigations')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _current.requiresConfirmation
                      ? 'Review and confirm the existing values before starting the pathway.'
                      : 'Enter all three values. Units are fixed by the Songyi backend contract.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('vitamin-d-input'),
                  controller: _vitaminD,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Vitamin D level (nmol/L)',
                  ),
                  validator: (value) => _validateNumber(value, allowZero: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('ionised-calcium-input'),
                  controller: _ionisedCalcium,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ionised calcium level (mmol/L)',
                  ),
                  validator: (value) => _validateNumber(value, allowZero: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('body-weight-input'),
                  controller: _bodyWeight,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Body weight (kg)',
                  ),
                  validator: (value) =>
                      _validateNumber(value, allowZero: false),
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
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving...' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
