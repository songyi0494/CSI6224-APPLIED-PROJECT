const clinicalLabels = <String, String>{
  'osteoporosisTreatmentStatus': 'Previous or current osteoporosis medicine',
  'age': 'Age in years',
  'sex': 'Sex at birth',
  'postmenopausal': 'Menopause has occurred',
  'minimalTraumaFracture': 'Fracture after a minor fall or injury',
  'fractureSite': 'Fracture site',
  'eGFR': 'Kidney function (eGFR)',
  'clinicalFrailtyScore': 'Clinical frailty score',
  'lifeExpectancy': 'Life expectancy recorded by a clinician (years)',
  'liveInResidentialCare': 'Lives in residential aged care',
  'knownPoorMedicationAdherence': 'Difficulty taking medicines as prescribed',
  'cognitiveImpairment': 'Diagnosed cognitive impairment',
  'testAvailable': 'Bone density test available',
  'testWithinLast2Years': 'Bone density test within the last 2 years',
  'T-score': 'Lowest recorded T-score',
  'vitaminDLevel': 'Recorded vitamin D result',
  'hipVertebralOrMultipleFracturesInLast24M':
      'Hip, spine or multiple fractures in the last 24 months',
  'highRisk': 'Very high fracture risk recorded by a clinician',
  'historyOfMiOrStroke': 'History of heart attack or stroke',
  'yearSincePostmenopausal': 'Years since menopause',
  'isRobustWoman': 'Robustness confirmed by a clinician',
};
String clinicalLabel(String key) =>
    clinicalLabels[key] ?? 'Additional clinical information';
String formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String factText(Object? value) => value == null
    ? 'Not provided'
    : value is bool
    ? (value ? 'Yes' : 'No')
    : value.toString();
