/// Display-only spelling and spacing; never mutates or infers treatment data.
String medicationDisplayValue(String field, Object? value) {
  if (value == null) {
    return field == 'duration' ? 'Not specified' : 'Not recorded';
  }
  final text = value.toString();
  if (field == 'dose') {
    return text.replaceAllMapped(
      RegExp(r'(\d)(mg|mcg|µg|μg|g|mL|ml|IU)\b'),
      (match) => '${match[1]} ${match[2]}',
    );
  }
  if (field == 'route') {
    return const {
          'subcut': 'Subcutaneous',
          'subcutaneous': 'Subcutaneous',
          'oral': 'Oral',
        }[text.toLowerCase()] ??
        text;
  }
  if (field == 'frequency') {
    return const {'6 monthly': 'Every 6 months'}[text.toLowerCase()] ?? text;
  }
  return text;
}
