import 'package:flutter/material.dart';

import '../models/app_user.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.onSignedIn, super.key});

  final ValueChanged<AppUser> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController(text: 'demo@example.com');
  final _passwordController = TextEditingController(text: 'password');
  UserRole _role = UserRole.clinician;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Osteoporosis Pathways',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Clinical decision support for osteoporosis care',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      SegmentedButton<UserRole>(
                        segments: const [
                          ButtonSegment(
                            value: UserRole.clinician,
                            label: Text('Clinician'),
                            icon: Icon(Icons.medical_services_outlined),
                          ),
                          ButtonSegment(
                            value: UserRole.patient,
                            label: Text('Patient'),
                            icon: Icon(Icons.person_outline),
                          ),
                        ],
                        selected: {_role},
                        onSelectionChanged: (roles) =>
                            setState(() => _role = roles.first),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _loading ? null : _signIn,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_loading ? 'Signing in' : 'Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) {
      return;
    }
    widget.onSignedIn(
      AppUser(
        id: _role == UserRole.clinician ? 'clinician-demo' : 'patient-demo',
        displayName:
            _role == UserRole.clinician ? 'Dr Demo Clinician' : 'Avery Martin',
        email: _emailController.text.trim(),
        role: _role,
      ),
    );
  }
}
