import 'package:flutter/material.dart';
import '../models/pathway_evaluation.dart';
import '../utils/medication_display.dart';

/// Preserve alternative care bundles and the alternative drugs inside each bundle.
class PathwayActionView extends StatelessWidget {
  const PathwayActionView({
    required this.action,
    this.compactMedications = false,
    super.key,
  });
  final PathwayAction action;
  final bool compactMedications;

  static const _columns = {
    'medication': 'Medication',
    'dose': 'Dose',
    'route': 'Route',
    'frequency': 'Frequency',
    'duration': 'Duration',
  };

  String _valueText(Object? value) {
    if (value is List) return value.map(_valueText).join('; ');
    if (value is Map) {
      return value.entries
          .map(
            (e) => '${_detailLabel(e.key.toString())}: ${_valueText(e.value)}',
          )
          .join('; ');
    }
    return value?.toString() ?? 'Not recorded';
  }

  String _detailLabel(String key) =>
      const {'requireReview': 'Clinician review required'}[key] ??
      key
          .replaceAll('_', ' ')
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (m) => '${m[1]} ${m[2]}',
          );

  Widget _clinicalAction(Map<String, dynamic> json) {
    if (json['type'] == 'pathwayRedirect') {
      final target = json['targetPathway']?.toString();
      final numberedPathway = target == null
          ? null
          : RegExp(r'^PATHWAY(\d+)$').firstMatch(target);
      return Text(
        target == null
            ? 'Recorded pathway transfer.'
            : 'Continue to ${numberedPathway != null ? 'Pathway ${numberedPathway[1]}' : _detailLabel(target)}.',
      );
    }
    final destination = json['destination'];
    final used = <String>{'type'};
    String primary;
    if (destination != null) {
      used.addAll(['destination', 'reason', 'when']);
      final place =
          const {
            'SPECIALIST': 'Specialist',
            'FRAGILE BONE CLINIC': 'Fragile bone clinic',
          }[destination] ??
          destination;
      final prefix = json['type'] == 'followUp' ? 'Follow up with' : 'Refer to';
      primary =
          '$prefix $place'
          '${json['reason'] == null ? '' : ': ${_valueText(json['reason'])}'}'
          '${json['when'] == null ? '' : '\nWhen: ${_valueText(json['when'])}'}';
    } else {
      final field = [
        'recommendation',
        'action',
        'instruction',
      ].where((key) => json[key] != null).firstOrNull;
      if (field != null) used.add(field);
      primary = field == null
          ? 'Recorded clinical action'
          : _valueText(json[field]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(primary),
        for (final entry in json.entries)
          if (!used.contains(entry.key))
            Text(
              '${_detailLabel(entry.key)}: ${entry.value is bool ? (entry.value == true ? 'Yes' : 'No') : _valueText(entry.value)}',
            ),
      ],
    );
  }

  Widget _columnsRow(BuildContext context, Map<String, dynamic>? medication) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in _columns.entries)
            Expanded(
              flex: entry.key == 'medication' ? 3 : 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  medication == null
                      ? entry.value
                      : medicationDisplayValue(
                          entry.key,
                          medication[entry.key],
                        ),
                  style: medication == null || entry.key == 'medication'
                      ? Theme.of(context).textTheme.titleSmall
                      : null,
                ),
              ),
            ),
        ],
      );

  Widget _medicationHeader(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth >= 600
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _columnsRow(context, null),
          )
        : const SizedBox.shrink(),
  );

  Widget _compactMedication(
    BuildContext context,
    Map<String, dynamic> json,
    bool showHeader,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeader) _medicationHeader(context),
      LayoutBuilder(
        builder: (_, constraints) => constraints.maxWidth >= 600
            ? _columnsRow(context, json)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicationDisplayValue('medication', json['medication']),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      for (final entry in _columns.entries)
                        if (entry.key != 'medication')
                          Text(
                            '${entry.value}: ${medicationDisplayValue(entry.key, json[entry.key])}',
                          ),
                    ],
                  ),
                ],
              ),
      ),
      for (final entry in json.entries)
        if (entry.key != 'type' && !_columns.containsKey(entry.key))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_detailLabel(entry.key)}: ${_valueText(entry.value)}',
            ),
          ),
    ],
  );

  Widget _render(
    BuildContext context,
    Object? value, {
    bool showMedicationHeader = true,
  }) {
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in value)
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
      if (compactMedications && !careAlternatives) {
        final allMedications = options.every(
          (option) => option is Map && option['medication'] != null,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Medication alternatives',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Alternatives for clinician review. These are not simultaneous prescriptions.',
            ),
            const SizedBox(height: 6),
            if (allMedications) _medicationHeader(context),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const Divider(height: 12),
              _render(
                context,
                options[i],
                showMedicationHeader: !allMedications,
              ),
            ],
          ],
        );
      }
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
      if (compactMedications) {
        return _compactMedication(context, json, showMedicationHeader);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              Text('${entry.value}: ${json[entry.key]}'),
        ],
      );
    }
    return compactMedications
        ? _clinicalAction(json)
        : Text(PathwayAction.fromJson(json).description);
  }

  @override
  Widget build(BuildContext context) => _render(context, action.raw);
}
