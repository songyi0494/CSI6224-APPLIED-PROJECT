import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import 'auth_signup.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.repository,
    required this.onSignedIn,
    super.key,
  });
  final AppRepository repository;
  final VoidCallback onSignedIn;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _loading = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.repository.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'We could not sign you in. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.health_and_safety_outlined, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'OsteoCare Pathway',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('Sign in to continue'),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'Enter your email',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter your email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter your password',
                        ),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter your password'
                            : null,
                        onFieldSubmitted: (_) {
                          if (!_loading) _signIn();
                        },
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _signIn,
                        child: Text(_loading ? 'Signing in...' : 'Sign in'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AuthSignUpScreen(
                                    repository: widget.repository,
                                  ),
                                ),
                              ),
                        child: const Text(
                          "Don't have an account? Create account",
                        ),
                      ),
                      if (widget.repository.isMock) ...[
                        const Divider(),
                        const Text(
                          'Demo mode — use synthetic information only.',
                        ),
                        const SizedBox(height: 8),
                        const SelectableText(
                          'patient@example.test\nclinician@example.test\nadmin@example.test\nPassword: DemoPass123!',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
