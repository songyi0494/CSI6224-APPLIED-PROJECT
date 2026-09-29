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
  bool _reviewing = false;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  RegistrationInput get _input => RegistrationInput(
    name: _name.text.trim(),
    email: _email.text.trim(),
    password: _password.text,
    role: _role,
    dateOfBirth: _birth,
    sexAtBirth: _sex,
  );

  void _review() {
    if (!_form.currentState!.validate()) return;
    if (_role == UserRole.patient && (_birth == null || _sex == null)) {
      setState(
        () => _error =
            'Please provide your date of birth and sex recorded at birth.',
      );
      return;
    }
    setState(() {
      _error = null;
      _reviewing = true;
    });
  }

  Future<void> _createAccount() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.signUp(_input);
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
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'We could not create your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: _reviewing
        ? RegistrationReview(
            input: _input,
            saving: _saving,
            error: _error,
            onBack: () => setState(() {
              _reviewing = false;
              _error = null;
            }),
            onCreateAccount: _createAccount,
          )
        : SingleChildScrollView(
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
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter your name'
                            : null,
                      ),
                      if (_role == UserRole.patient) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            _birth == null
                                ? 'Date of birth'
                                : formatDate(_birth!),
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
                                  if (date != null && mounted) {
                                    setState(() => _birth = date);
                                  }
                                },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _sex,
                          decoration: const InputDecoration(
                            labelText: 'Sex recorded at birth',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'male',
                              child: Text('Male'),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Female'),
                            ),
                            DropdownMenuItem(
                              value: 'another_term',
                              child: Text('Another term'),
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
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
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
                        validator: (v) => v != _password.text
                            ? 'Passwords do not match'
                            : null,
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
                        key: const Key('registration-review-button'),
                        onPressed: _saving ? null : _review,
                        child: const Text('Review details'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

class RegistrationReview extends StatelessWidget {
  const RegistrationReview({
    required this.input,
    required this.saving,
    required this.onBack,
    required this.onCreateAccount,
    this.error,
    super.key,
  });

  final RegistrationInput input;
  final bool saving;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

  String get _accountType => switch (input.role) {
    UserRole.patient => 'Patient',
    UserRole.clinician => 'Clinician',
    UserRole.admin => 'Administrator',
  };

  String get _sexLabel => sexRecordedAtBirthText(input.sexAtBirth);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review your details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Check these details before creating your account.'),
            const SizedBox(height: 20),
            _ReviewRow(label: 'Full name', value: input.name),
            _ReviewRow(label: 'Account type', value: _accountType),
            if (input.role == UserRole.patient) ...[
              _ReviewRow(
                label: 'Date of birth',
                value: input.dateOfBirth == null
                    ? 'Not provided'
                    : formatDate(input.dateOfBirth!),
              ),
              _ReviewRow(label: 'Sex recorded at birth', value: _sexLabel),
            ],
            _ReviewRow(label: 'Email', value: input.email),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            OutlinedButton(
              key: const Key('registration-back-button'),
              onPressed: saving ? null : onBack,
              child: const Text('Back to edit'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('registration-create-button'),
              onPressed: saving ? null : onCreateAccount,
              child: Text(saving ? 'Creating account...' : 'Create account'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
