class CaseInvestigations {
  const CaseInvestigations({
    required this.caseId,
    required this.vitaminDLevel,
    required this.ionisedCalcium,
    required this.bodyWeightKg,
    required this.revision,
    required this.isComplete,
    this.completedAt,
    this.updatedAt,
    this.authoritativeHypocalcaemia,
    this.hypocalcaemiaRevision = 0,
  });

  static const vitaminDUnit = 'nmol/L';
  static const ionisedCalciumUnit = 'mmol/L';
  static const bodyWeightUnit = 'kg';

  final String caseId;
  final double? vitaminDLevel;
  final double? ionisedCalcium;
  final double? bodyWeightKg;
  final bool? authoritativeHypocalcaemia;
  final int hypocalcaemiaRevision;
  final int revision;
  final bool isComplete;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  bool get hasAnyValue =>
      vitaminDLevel != null || ionisedCalcium != null || bodyWeightKg != null;

  bool get requiresConfirmation => revision == 0 && hasAnyValue;

  bool get canStartPathway => isComplete && revision > 0;

  factory CaseInvestigations.empty(String caseId) => CaseInvestigations(
    caseId: caseId,
    vitaminDLevel: null,
    ionisedCalcium: null,
    bodyWeightKg: null,
    revision: 0,
    isComplete: false,
  );

  factory CaseInvestigations.fromRpcJson(Map<String, dynamic> json) {
    final caseId = json['caseId']?.toString();
    final revision = _integer(json['revision']);
    final serverComplete = json['completed'];
    if (caseId == null || caseId.isEmpty || revision == null || revision < 0) {
      throw const FormatException('Invalid investigations identity.');
    }
    if (serverComplete is! bool) {
      throw const FormatException('Invalid investigations completion state.');
    }

    final vitaminD = _measurement(
      json['vitaminD'],
      expectedUnit: vitaminDUnit,
      allowZero: true,
    );
    final ionisedCalcium = _measurement(
      json['ionisedCalcium'],
      expectedUnit: ionisedCalciumUnit,
      allowZero: true,
    );
    final bodyWeight = _measurement(
      json['bodyWeight'],
      expectedUnit: bodyWeightUnit,
      allowZero: false,
    );

    // The server remains authoritative for completion. Flutter only fails
    // closed when a response contradicts the revision/value contract.
    final contractComplete = serverComplete && revision > 0;

    return CaseInvestigations(
      caseId: caseId,
      vitaminDLevel: vitaminD,
      ionisedCalcium: ionisedCalcium,
      bodyWeightKg: bodyWeight,
      authoritativeHypocalcaemia:
          json['authoritativeHypocalcaemia'] is bool &&
              (_integer(json['hypocalcaemiaRevision']) ?? 0) > 0
          ? json['authoritativeHypocalcaemia'] as bool
          : null,
      hypocalcaemiaRevision: _integer(json['hypocalcaemiaRevision']) ?? 0,
      revision: revision,
      isComplete: contractComplete,
      completedAt: _date(json['completedAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  static double? _measurement(
    Object? raw, {
    required String expectedUnit,
    required bool allowZero,
  }) {
    if (raw is! Map) {
      throw const FormatException('Invalid investigation measurement.');
    }
    final value = raw['value'];
    final unit = raw['unit']?.toString();
    if (unit != expectedUnit) {
      throw const FormatException('Unexpected investigation unit.');
    }
    if (value == null) return null;
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null ||
        !parsed.isFinite ||
        (allowZero ? parsed < 0 : parsed <= 0)) {
      throw const FormatException('Invalid investigation value.');
    }
    return parsed;
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
}
