import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}
