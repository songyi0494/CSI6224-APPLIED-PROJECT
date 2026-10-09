import 'package:flutter/material.dart';
import '../models/live_pathway.dart';

/// Groups exclusions visually while retaining the exact canonical site fact.
/// The group marker is never emitted to the repository.
class FractureSiteField extends StatefulWidget {
  const FractureSiteField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  State<FractureSiteField> createState() => _FractureSiteFieldState();
}

class _FractureSiteFieldState extends State<FractureSiteField> {
  static const excluded = {'hand', 'foot', 'face', 'ankle'};
  static const group = '_excluded_group';
  late bool showExcluded = excluded.contains(widget.value);
  @override
  void didUpdateWidget(covariant FractureSiteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null) showExcluded = excluded.contains(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final choices = pathwayFactRegistry['fractureSite']!.choices;
    final groupedValue = showExcluded ? group : widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('fracture-group-$groupedValue'),
          initialValue: groupedValue,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Select an answer'),
          items: [
            for (final entry in choices.entries.where(
              (e) => !excluded.contains(e.key) && e.key != 'not_sure',
            ))
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.key == 'forearm' ? 'Wrist / forearm' : entry.value,
                ),
              ),
            const DropdownMenuItem(
              value: group,
              child: Text('Excluded site — hand, foot, face, or ankle'),
            ),
            const DropdownMenuItem(value: 'not_sure', child: Text('Not sure')),
          ],
          onChanged: widget.enabled
              ? (value) {
                  setState(() => showExcluded = value == group);
                  widget.onChanged(value == group ? null : value);
                }
              : null,
          validator: (_) => widget.value == null
              ? 'Clinician confirmation is required'
              : null,
        ),
        if (showExcluded) ...[
          const SizedBox(height: 12),
          const Text(
            'Hand, foot, face, and ankle fractures are not eligible for the general minimal-trauma-fracture pathway.',
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('excluded-${widget.value}'),
            initialValue: excluded.contains(widget.value) ? widget.value : null,
            decoration: const InputDecoration(
              labelText: 'Record the excluded fracture site',
              hintText: 'Select an answer',
            ),
            items: [
              for (final key in excluded)
                DropdownMenuItem(value: key, child: Text(choices[key]!)),
            ],
            onChanged: widget.enabled ? widget.onChanged : null,
            validator: (value) =>
                value == null ? 'Select the recorded fracture site' : null,
          ),
        ],
        if (widget.value == 'not_sure') ...[
          const SizedBox(height: 12),
          const Text('More information is required.'),
        ],
      ],
    );
  }
}
