import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../utils/clinical_labels.dart';

class AuthSignUpScreen extends StatefulWidget {
  const AuthSignUpScreen({required this.repository, super.key});
  final AppRepository repository;
  @override
  State<AuthSignUpScreen> createState() => _AuthSignUpScreenState();
}

class _AuthSignUpScreenState extends State<AuthSignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  UserRole _role = UserRole.patient;
  DateTime? _birth;
  String? _sex;
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_role == UserRole.patient && (_birth == null || _sex == null)) {
      setState(
        () => _error = 'Please provide your date of birth and sex at birth.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.signUp(
        RegistrationInput(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          role: _role,
          dateOfBirth: _birth,
          sexAtBirth: _sex,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _role == UserRole.clinician
                ? 'Account created. Verify your email if requested. Your clinician account needs administrator approval.'
                : 'Account created. Check your email for verification instructions, then sign in.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'We could not create your account. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('I am registering as:'),
                const SizedBox(height: 12),
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                      value: UserRole.patient,
                      label: Text('Patient'),
                    ),
                    ButtonSegment(
                      value: UserRole.clinician,
                      label: Text('Clinician'),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: _saving
                      ? null
                      : (v) => setState(() => _role = v.first),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter your name' : null,
                ),
                if (_role == UserRole.patient) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _birth == null ? 'Date of birth' : formatDate(_birth!),
                    ),
                    onPressed: _saving
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now(),
                              initialDate: _birth,
                            );
                            if (date != null && mounted)
                              setState(() => _birth = date);
                          },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(
                      labelText: 'Sex at birth',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Female')),
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
                    onChanged: (v) => setState(() => _sex = v),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: _role == UserRole.clinician
                        ? 'Official / professional email'
                        : 'Email',
                  ),
                  validator: (v) => v == null || !v.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => v == null || v.length < 8
                      ? 'Use at least 8 characters'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  validator: (v) =>
                      v != _password.text ? 'Passwords do not match' : null,
                ),
                if (_role == UserRole.clinician)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Your clinician account must be approved before you can review assessments.',
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving ? 'Creating account...' : 'Create account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
