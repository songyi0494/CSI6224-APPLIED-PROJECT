import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../models/app_user.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/async_panel.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    required this.user,
    required this.repository,
    required this.onSignOut,
    super.key,
  });
  final AppUser user;
  final AppRepository repository;
  final VoidCallback onSignOut;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _saving = false;
  String? _error;
  Future<void> _review(
    String id,
    ClinicianApprovalStatus status,
    VoidCallback reload,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.reviewClinician(id, status);
      if (mounted) reload();
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'The account could not be updated. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Clinician approvals',
    user: widget.user,
    onSignOut: widget.onSignOut,
    child: AsyncPanel<List<AppUser>>(
      load: widget.repository.pendingClinicians,
      builder: (users, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OsteoCare Pathway',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pending clinicians',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _saving ? null : reload,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (widget.repository.isMock)
            const Text('Demo mode — approvals last for this app session.'),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No clinician accounts are waiting for approval.'),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final user in users)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(user.email),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _review(
                                    user.id,
                                    ClinicianApprovalStatus.approved,
                                    reload,
                                  ),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _review(
                                    user.id,
                                    ClinicianApprovalStatus.rejected,
                                    reload,
                                  ),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
