class Pathway1ClinicianInput {
  const Pathway1ClinicianInput({
    this.egfr,
    this.adherenceConcern,
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
    this.tScoreAtOrBelowMinus2_5AnySite,
    this.veryHighFractureRisk,
    this.frailtyResidentialOrLimitedLifeExpectancy,
  });

  // Raw score/site and the old risk flag can be read from history, but are
  // not emitted by toJson or toEvaluatorFacts as current decision authority.
  final double? lifeExpectancy, tScoreValue, yearsSinceMenopause;
  final bool? egfr, adherenceConcern;
  final bool? tScoreAtOrBelowMinus2_5AnySite,
      veryHighFractureRisk,
      frailtyResidentialOrLimitedLifeExpectancy;
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
    put('adherenceConcern', adherenceConcern);
    put('dxaDoneWithinPrevious2Years', dxaDoneWithinPrevious2Years);
    put('dxaImpractical', dxaImpractical);
    put('tScoreAtOrBelowMinus2_5AnySite', tScoreAtOrBelowMinus2_5AnySite);
    put('veryHighFractureRisk', veryHighFractureRisk);
    put(
      'frailtyResidentialOrLimitedLifeExpectancy',
      frailtyResidentialOrLimitedLifeExpectancy,
    );
    put(
      'hipVertebralOrMultipleFracturesInLast24M',
      hipVertebralOrMultipleFracturesInLast24M,
    );
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
    put('adherenceConcern', adherenceConcern);
    if (dxaImpractical != null) {
      facts['testAvailable'] = !dxaImpractical!;
    }
    put('testWithinLast2Years', dxaDoneWithinPrevious2Years);
    put('tScoreAtOrBelowMinus2_5AnySite', tScoreAtOrBelowMinus2_5AnySite);
    put('veryHighFractureRisk', veryHighFractureRisk);
    put(
      'frailtyResidentialOrLimitedLifeExpectancy',
      frailtyResidentialOrLimitedLifeExpectancy,
    );
    put(
      'hipVertebralOrMultipleFracturesInLast24M',
      hipVertebralOrMultipleFracturesInLast24M,
    );
    put('yearSincePostmenopausal', yearsSinceMenopause);
    put('isRobustWoman', robustWoman);
    return facts;
  }

  factory Pathway1ClinicianInput.fromJson(Map<String, dynamic>? json) {
    final f = json ?? const <String, dynamic>{};
    return Pathway1ClinicianInput(
      adherenceConcern: f['adherenceConcern'] is bool
          ? f['adherenceConcern'] as bool
          : null,
      // Historical raw numbers require a new threshold confirmation.
      egfr: f['eGFR'] is bool ? f['eGFR'] as bool : null,
      frailtyResidentialOrLimitedLifeExpectancy:
          f['frailtyResidentialOrLimitedLifeExpectancy'] is bool
          ? f['frailtyResidentialOrLimitedLifeExpectancy'] as bool
          : null,
      tScoreAtOrBelowMinus2_5AnySite:
          f['tScoreAtOrBelowMinus2_5AnySite'] is bool
          ? f['tScoreAtOrBelowMinus2_5AnySite'] as bool
          : null,
      veryHighFractureRisk: f['veryHighFractureRisk'] is bool
          ? f['veryHighFractureRisk'] as bool
          : null,
      clinicalFrailtyScore: f['clinicalFrailtyScore'] is num
          ? (f['clinicalFrailtyScore'] as num).toInt()
          : null,
      lifeExpectancy: f['lifeExpectancy'] is num
          ? (f['lifeExpectancy'] as num).toDouble()
          : null,
      knownPoorMedicationAdherence: f['knownPoorMedicationAdherence'] as bool?,
      cognitiveImpairment: f['cognitiveImpairment'] as bool?,
      dxaDoneWithinPrevious2Years: f['dxaDoneWithinPrevious2Years'] as bool?,
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
