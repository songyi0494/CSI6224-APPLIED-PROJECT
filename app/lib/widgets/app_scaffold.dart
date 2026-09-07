import 'package:flutter/material.dart';

import '../models/app_user.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.user,
    required this.onSignOut,
    required this.child,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final AppUser user;
  final VoidCallback onSignOut;
  final Widget child;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(user.displayName)),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );
  }
}
