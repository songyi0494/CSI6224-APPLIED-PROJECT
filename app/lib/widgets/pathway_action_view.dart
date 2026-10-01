import 'package:flutter/material.dart';
import '../models/pathway_evaluation.dart';

/// Preserve alternative care bundles and the alternative drugs inside each bundle.
class PathwayActionView extends StatelessWidget {
  const PathwayActionView({required this.action, super.key});
  final PathwayAction action;

  Widget _render(BuildContext context, Object? value) {
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final child in value)
          Padding(padding: const EdgeInsets.only(bottom: 10),
            child: _render(context, child))],
      );
    }
    if (value is! Map) return Text(value?.toString() ?? 'Details unavailable');
    final json = Map<String, dynamic>.from(value);
    final options = json['options'];
    if (options is List) {
      final careAlternatives = json['type'] == 'actionOptions';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(careAlternatives ? 'Alternative care plans' : 'Medication alternatives',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (careAlternatives) ...[
                      Text('Care plan ${i + 1}',
                        style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 10),
                    ],
                    _render(context, options[i]),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (json['medication'] != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(json['medication'].toString(),
            style: Theme.of(context).textTheme.titleSmall),
          for (final entry in const {'dose': 'Dose', 'route': 'Route',
            'frequency': 'Frequency', 'duration': 'Duration'}.entries)
            if (json[entry.key] != null)
              Text('${entry.value}: ${json[entry.key]}'),
        ],
      );
    }
    return Text(PathwayAction.fromJson(json).description);
  }

  @override
  Widget build(BuildContext context) => _render(context, action.raw);
}
