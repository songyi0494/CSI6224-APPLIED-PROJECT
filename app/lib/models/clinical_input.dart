class ClinicalInput {
  const ClinicalInput({
    this.treated,
    this.age,
    this.sexAtBirth,
    this.postmenopausal,
    this.minimalTraumaFracture,
    this.fractureSite,
    this.egfr,
    this.adherenceConcern,
    this.frailty,
    this.lifeExpectancy,
    this.residentialCare,
    this.poorAdherence,
    this.cognitiveImpairment,
    this.dxaAvailable,
    this.dxaRecent,
    this.tScore,
    this.vitaminD,
    this.recentMajorFracture,
    this.highRisk,
    this.tScoreAtOrBelowMinus2_5AnySite,
    this.veryHighFractureRisk,
    this.frailtyResidentialOrLimitedLifeExpectancy,
    this.miOrStroke,
    this.yearsSinceMenopause,
    this.robustWoman,
  });
  final bool? treated,
      postmenopausal,
      minimalTraumaFracture,
      residentialCare,
      poorAdherence,
      cognitiveImpairment,
      dxaAvailable,
      dxaRecent,
      recentMajorFracture,
      highRisk,
      miOrStroke,
      robustWoman;
  final int? age, frailty;
  final String? sexAtBirth, fractureSite;
  // tScore and highRisk are retained for reading historical records only.
  // Current decision maps emit the two named Boolean confirmations instead.
  final double? lifeExpectancy, tScore, vitaminD, yearsSinceMenopause;
  final bool? egfr, adherenceConcern;
  final bool? tScoreAtOrBelowMinus2_5AnySite,
      veryHighFractureRisk,
      frailtyResidentialOrLimitedLifeExpectancy;

  // retain the existing JSON rule vocabulary at this single boundary
  Map<String, Object?> toFacts() => {
    'osteoporosisTreatmentStatus': treated,
    'age': age,
    'sex': sexAtBirth,
    'postmenopausal': postmenopausal,
    'minimalTraumaFracture': minimalTraumaFracture,
    'fractureSite': fractureSite,
    'eGFR': egfr,
    'tScoreAtOrBelowMinus2_5AnySite': tScoreAtOrBelowMinus2_5AnySite,
    'veryHighFractureRisk': veryHighFractureRisk,
    'frailtyResidentialOrLimitedLifeExpectancy':
        frailtyResidentialOrLimitedLifeExpectancy,
    'adherenceConcern': adherenceConcern,
    'testAvailable': dxaAvailable,
    'testWithinLast2Years': dxaRecent,
    'vitaminDLevel': vitaminD,
    'hipVertebralOrMultipleFracturesInLast24M': recentMajorFracture,
    'historyOfMiOrStroke': miOrStroke,
    'yearSincePostmenopausal': yearsSinceMenopause,
    'isRobustWoman': robustWoman,
  };
  factory ClinicalInput.fromFacts(Map<String, dynamic> f) => ClinicalInput(
    adherenceConcern: f['adherenceConcern'] is bool
        ? f['adherenceConcern'] as bool
        : null,
    treated: f['osteoporosisTreatmentStatus'] as bool?,
    age: (f['age'] as num?)?.toInt(),
    sexAtBirth: f['sex'] as String?,
    postmenopausal: f['postmenopausal'] as bool?,
    minimalTraumaFracture: f['minimalTraumaFracture'] as bool?,
    fractureSite: f['fractureSite'] as String?,
    egfr: f['eGFR'] is bool ? f['eGFR'] as bool : null,
    frailtyResidentialOrLimitedLifeExpectancy:
        f['frailtyResidentialOrLimitedLifeExpectancy'] is bool
        ? f['frailtyResidentialOrLimitedLifeExpectancy'] as bool
        : null,
    tScoreAtOrBelowMinus2_5AnySite: f['tScoreAtOrBelowMinus2_5AnySite'] is bool
        ? f['tScoreAtOrBelowMinus2_5AnySite'] as bool
        : null,
    veryHighFractureRisk: f['veryHighFractureRisk'] is bool
        ? f['veryHighFractureRisk'] as bool
        : null,
    frailty: f['clinicalFrailtyScore'] is num
        ? (f['clinicalFrailtyScore'] as num).toInt()
        : null,
    lifeExpectancy: f['lifeExpectancy'] is num
        ? (f['lifeExpectancy'] as num).toDouble()
        : null,
    residentialCare: f['liveInResidentialCare'] is bool
        ? f['liveInResidentialCare'] as bool
        : null,
    poorAdherence: f['knownPoorMedicationAdherence'] as bool?,
    cognitiveImpairment: f['cognitiveImpairment'] as bool?,
    dxaAvailable: f['testAvailable'] as bool?,
    dxaRecent: f['testWithinLast2Years'] as bool?,
    tScore: (f['T-score'] as num?)?.toDouble(),
    vitaminD: (f['vitaminDLevel'] as num?)?.toDouble(),
    recentMajorFracture: f['hipVertebralOrMultipleFracturesInLast24M'] as bool?,
    highRisk: f['highRisk'] as bool?,
    miOrStroke: f['historyOfMiOrStroke'] as bool?,
    yearsSinceMenopause: (f['yearSincePostmenopausal'] as num?)?.toDouble(),
    robustWoman: f['isRobustWoman'] as bool?,
  );
}
