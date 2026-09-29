class Pathway1ClinicianInput {
  const Pathway1ClinicianInput({
    this.egfr,
    this.clinicalFrailtyScore,
    this.lifeExpectancy,
    this.knownPoorMedicationAdherence,
    this.cognitiveImpairment,
    this.dxaDoneWithinPrevious2Years,
    this.dxaImpractical,
    this.tScoreValue,
    this.tScoreSite,
    this.hipVertebralOrMultipleFracturesInLast24M,
    this.clinicianConfirmedVeryHighRisk,
    this.yearsSinceMenopause,
    this.robustWoman,
  });

  final double? egfr, lifeExpectancy, tScoreValue, yearsSinceMenopause;
  final int? clinicalFrailtyScore;
  final String? tScoreSite;
  final bool? knownPoorMedicationAdherence,
      cognitiveImpairment,
      dxaDoneWithinPrevious2Years,
      dxaImpractical,
      hipVertebralOrMultipleFracturesInLast24M,
      clinicianConfirmedVeryHighRisk,
      robustWoman;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('eGFR', egfr);
    put('clinicalFrailtyScore', clinicalFrailtyScore);
    put('lifeExpectancy', lifeExpectancy);
    put('knownPoorMedicationAdherence', knownPoorMedicationAdherence);
    put('cognitiveImpairment', cognitiveImpairment);
    put('dxaDoneWithinPrevious2Years', dxaDoneWithinPrevious2Years);
    put('dxaImpractical', dxaImpractical);
    put('tScoreValue', tScoreValue);
    put('tScoreSite', tScoreSite);
    put(
      'hipVertebralOrMultipleFracturesInLast24M',
      hipVertebralOrMultipleFracturesInLast24M,
    );
    put('clinicianConfirmedVeryHighRisk', clinicianConfirmedVeryHighRisk);
    put('yearsSinceMenopause', yearsSinceMenopause);
    put('robustWoman', robustWoman);
    return json;
  }

  Map<String, Object?> toEvaluatorFacts() {
    final facts = <String, Object?>{};
    void put(String key, Object? value) {
      if (value != null) facts[key] = value;
    }

    put('eGFR', egfr);
    put('clinicalFrailtyScore', clinicalFrailtyScore);
    put('lifeExpectancy', lifeExpectancy);
    put('knownPoorMedicationAdherence', knownPoorMedicationAdherence);
    put('cognitiveImpairment', cognitiveImpairment);
    if (dxaImpractical != null) {
      facts['testAvailable'] = !dxaImpractical!;
    }
    put('testWithinLast2Years', dxaDoneWithinPrevious2Years);
    put('T-score', tScoreValue);
    put('tScoreSite', tScoreSite);
    put(
      'hipVertebralOrMultipleFracturesInLast24M',
      hipVertebralOrMultipleFracturesInLast24M,
    );
    put('highRisk', clinicianConfirmedVeryHighRisk);
    put('yearSincePostmenopausal', yearsSinceMenopause);
    put('isRobustWoman', robustWoman);
    return facts;
  }

  factory Pathway1ClinicianInput.fromJson(Map<String, dynamic>? json) {
    final f = json ?? const <String, dynamic>{};
    return Pathway1ClinicianInput(
      egfr: (f['eGFR'] as num?)?.toDouble(),
      clinicalFrailtyScore: (f['clinicalFrailtyScore'] as num?)?.toInt(),
      lifeExpectancy: (f['lifeExpectancy'] as num?)?.toDouble(),
      knownPoorMedicationAdherence:
          f['knownPoorMedicationAdherence'] as bool?,
      cognitiveImpairment: f['cognitiveImpairment'] as bool?,
      dxaDoneWithinPrevious2Years:
          f['dxaDoneWithinPrevious2Years'] as bool?,
      dxaImpractical: f['dxaImpractical'] as bool?,
      tScoreValue: (f['tScoreValue'] as num?)?.toDouble(),
      tScoreSite: f['tScoreSite'] as String?,
      hipVertebralOrMultipleFracturesInLast24M:
          f['hipVertebralOrMultipleFracturesInLast24M'] as bool?,
      clinicianConfirmedVeryHighRisk:
          f['clinicianConfirmedVeryHighRisk'] as bool?,
      yearsSinceMenopause: (f['yearsSinceMenopause'] as num?)?.toDouble(),
      robustWoman: f['robustWoman'] as bool?,
    );
  }
}
