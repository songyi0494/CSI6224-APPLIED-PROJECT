import 'package:flutter/material.dart';
import '../models/pathway_evaluation.dart';

/// Preserve alternative care bundles and the alternative drugs inside each bundle.
enum PatientActionSection { treatment, followUp }

class PathwayActionView extends StatelessWidget {
  const PathwayActionView({
    required this.action,
    this.patientSection,
    super.key,
  });
  final PathwayAction action;
  final PatientActionSection? patientSection;

  static bool hasContent(Object? value, PatientActionSection section) {
    if (value is List) return value.any((child) => hasContent(child, section));
    if (value is! Map) return section == PatientActionSection.treatment;
    if (value['options'] is List) {
      return (value['options'] as List).any(
        (child) => hasContent(child, section),
      );
    }
    final followUp = value['type'] == 'followUp' || value['type'] == 'review';
    return section == PatientActionSection.followUp ? followUp : !followUp;
  }

  bool _visible(Object? value) {
    if (patientSection == null) return true;
    return hasContent(value, patientSection!);
  }

  Widget _render(BuildContext context, Object? value) {
    if (!_visible(value)) return const SizedBox.shrink();
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in value)
            if (_visible(child))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _render(context, child),
              ),
        ],
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
          Text(
            careAlternatives
                ? 'Alternative care plans'
                : 'Medication alternatives',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < options.length; i++)
            if (_visible(options[i]))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (careAlternatives) ...[
                        Text(
                          'Care plan ${i + 1}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
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
          Text('Medication', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            json['medication'].toString(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final entry in const {
            'dose': 'Dose',
            'route': 'Route',
            'frequency': 'Frequency',
            'duration': 'Duration',
          }.entries)
            if (json[entry.key] != null)
              Text(
                '${entry.value}: ${_display(entry.key, json[entry.key].toString())}',
              ),
        ],
      );
    }
    if (json['type'] == 'followUp') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (patientSection == null)
            Text('Follow-up', style: Theme.of(context).textTheme.titleMedium),
          Text('${PathwayAction.fromJson(json).description}.'),
        ],
      );
    }
    return Text(PathwayAction.fromJson(json).description);
  }

  String _display(String key, String value) {
    if (key == 'route' && value == 'subcut') return 'subcutaneous';
    if (key == 'frequency' && value == '6 monthly') return 'every 6 months';
    if (key == 'dose') {
      return value.replaceAllMapped(
        RegExp(r'(\d)(mg|microg)\b'),
        (m) => '${m[1]} ${m[2]}',
      );
    }
    return value;
  }

  @override
  Widget build(BuildContext context) => _render(context, action.raw);
}
