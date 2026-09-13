import 'dart:async';
import 'package:flutter/material.dart';
import 'data/app_repository.dart';
import 'models/app_user.dart';
import 'screens/auth_screen.dart';
import 'screens/patient_home_screen.dart';
import 'screens/clinician_dashboard_screen.dart';
import 'screens/admin_screen.dart';
import 'theme/app_theme.dart';

class OsteoporosisPathwaysApp extends StatefulWidget {
  const OsteoporosisPathwaysApp({required this.repository, super.key});
  final AppRepository repository;
  @override
  State<OsteoporosisPathwaysApp> createState() =>
      _OsteoporosisPathwaysAppState();
}

class _OsteoporosisPathwaysAppState extends State<OsteoporosisPathwaysApp>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  AppUser? _user;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.repository.sessionChanges.listen((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_user != null) _refresh();
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_generation;
    try {
      final user = await widget.repository.loadProfile();
      if (mounted && request == _generation)
        setState(() {
          _user = user;
          _error = null;
          _loading = false;
        });
    } catch (e) {
      if (mounted && request == _generation)
        setState(() {
          _user = null;
          _loading = false;
          _error = e is AppException
              ? e.message
              : 'We could not load your account. Please try again.';
        });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.repository.signOut();
      await _refresh();
    } catch (e) {
      if (mounted)
        setState(() => _error = 'We could not sign you out. Please try again.');
    }
  }

  Widget _home() {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return _accountMessage('Account unavailable', _error!);
    final user = _user;
    if (user == null)
      return AuthScreen(repository: widget.repository, onSignedIn: _refresh);
    switch (user.role) {
      case UserRole.patient:
        return PatientHomeScreen(
          user: user,
          repository: widget.repository,
          onSignOut: _signOut,
        );
      case UserRole.admin:
        return AdminScreen(
          user: user,
          repository: widget.repository,
          onSignOut: _signOut,
        );
      case UserRole.clinician:
        if (user.approvalStatus == ClinicianApprovalStatus.approved)
          return ClinicianDashboardScreen(
            user: user,
            repository: widget.repository,
            onSignOut: _signOut,
          );
        if (user.approvalStatus == ClinicianApprovalStatus.pending)
          return _accountMessage(
            'Account awaiting approval',
            'Thanks for registering. Your clinician account has been submitted for review. You can access the clinician dashboard after your account is approved.',
          );
        return _accountMessage(
          'Account not approved',
          'Your clinician account has not been approved. Please contact the system administrator if you believe this is an error.',
        );
    }
  }

  Widget _accountMessage(String title, String text) => Scaffold(
    appBar: AppBar(title: const Text('OsteoCare Pathway')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(text),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('Try again'),
              ),
              TextButton(onPressed: _signOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    // replacing the navigator discards protected screens after a session change
    key: ValueKey('${_user?.sessionKey}/${_error != null}/${_loading}'),
    title: 'OsteoCare Pathway',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: _home(),
  );
}
