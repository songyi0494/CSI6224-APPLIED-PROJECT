import 'package:flutter/material.dart';
import '../data/app_repository.dart';

/// Reuses the repository's existing session sign-out. The app's session listener
/// clears protected routes when the session changes.
class GlobalSignOut extends StatelessWidget {
  const GlobalSignOut({required this.repository, super.key});
  final AppRepository repository;
  @override
  Widget build(BuildContext context) => GlobalSignOutButton(
    onPressed: () async {
      try {
        await repository.signOut();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sign out could not be completed. Please try again.',
              ),
            ),
          );
        }
      }
    },
  );
}

class GlobalSignOutButton extends StatelessWidget {
  const GlobalSignOutButton({required this.onPressed, super.key});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Sign out',
    child: TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.logout, size: 18),
      label: const Text('Sign out'),
    ),
  );
}
