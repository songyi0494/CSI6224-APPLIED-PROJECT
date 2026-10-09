enum PathwayFactKind { boolean, number, choice }

class PathwayFactDefinition {
  const PathwayFactDefinition({
    required this.key,
    required this.label,
    required this.kind,
    this.unit,
    this.wholeNumber = false,
    this.allowNegative = false,
    this.choices = const {},
    this.helperText,
  });

  final String key;
  final String label;
  final PathwayFactKind kind;
  final String? unit;
  final bool wholeNumber;
  final bool allowNegative;
  final Map<String, String> choices;
  final String? helperText;

  bool accepts(Object? value) => switch (kind) {
    PathwayFactKind.boolean => value is bool,
    PathwayFactKind.number => value is num && value.isFinite,
    PathwayFactKind.choice => value is String && choices.containsKey(value),
  };
}

/// Editable facts for the local P1/P2 rule contract.
/// Demographic eligibility is supplied by the protected server context.
const pathwayFactRegistry = <String, PathwayFactDefinition>{
  'eGFR': PathwayFactDefinition(
    key: 'eGFR',
    label: 'eGFR ≥30 mL/min?',
    kind: PathwayFactKind.boolean,
  ),
  'minimalTraumaFracture': PathwayFactDefinition(
    key: 'minimalTraumaFracture',
    label: 'Did the fracture occur after a fall from standing height or less?',
    kind: PathwayFactKind.choice,
    choices: {'yes': 'Yes', 'no': 'No', 'not_sure': 'Not sure'},
  ),
  'fractureSite': PathwayFactDefinition(
    key: 'fractureSite',
    label: 'Fracture site',
    kind: PathwayFactKind.choice,
    choices: {
      'hip': 'Hip',
      'vertebral': 'Spine',
      'pelvis': 'Pelvis',
      'upper_arm': 'Upper arm',
      'forearm': 'Forearm',
      'leg': 'Leg',
      'ribs': 'Ribs',
      'hand': 'Hand',
      'foot': 'Foot',
      'face': 'Face',
      'ankle': 'Ankle',
      'not_sure': 'Not sure',
    },
  ),
  'osteoporosisTreatmentStatus': PathwayFactDefinition(
    key: 'osteoporosisTreatmentStatus',
    label: 'Currently on osteoporosis treatment',
    kind: PathwayFactKind.boolean,
  ),
  'frailtyResidentialOrLimitedLifeExpectancy': PathwayFactDefinition(
    key: 'frailtyResidentialOrLimitedLifeExpectancy',
    label: 'Does the patient have any of these factors?',
    helperText:
        'Lives in residential care, Clinical Frailty Scale score 6 or higher, or life expectancy less than 7 years.',
    kind: PathwayFactKind.boolean,
  ),
  'adherenceConcern': PathwayFactDefinition(
    key: 'adherenceConcern',
    label:
        "Is there concern about the patient's ability to follow the treatment plan?",
    helperText:
        'Examples include difficulty taking medicines as prescribed or cognitive impairment.',
    kind: PathwayFactKind.boolean,
  ),
  'tScoreAtOrBelowMinus2_5AnySite': PathwayFactDefinition(
    key: 'tScoreAtOrBelowMinus2_5AnySite',
    label: 'Is the T-score -2.5 or lower at any of these sites?',
    helperText: 'Femoral neck, hip, or lumbar spine.',
    kind: PathwayFactKind.boolean,
  ),
  'veryHighFractureRisk': PathwayFactDefinition(
    key: 'veryHighFractureRisk',
    label: 'Does the patient meet the very-high-fracture-risk criteria?',
    helperText:
        'T-score ≤ -3.0, plus at least one of: recent fracture within 2 years, two or more fractures, relevant clinical risk factors, FRAX major risk ≥30%, or FRAX hip risk ≥4.5%.',
    kind: PathwayFactKind.boolean,
  ),
  'testAvailability': PathwayFactDefinition(
    key: 'testAvailability',
    label: 'BMD DXA available or completed within two years',
    kind: PathwayFactKind.boolean,
  ),
  'hipVertebralOrMultipleFracturesInLast24M': PathwayFactDefinition(
    key: 'hipVertebralOrMultipleFracturesInLast24M',
    label: 'Hip, vertebral, or multiple fractures in the last 24 months',
    kind: PathwayFactKind.boolean,
  ),
  'antiresorptiveTreatmentStatus': PathwayFactDefinition(
    key: 'antiresorptiveTreatmentStatus',
    label: 'Currently on antiresorptive treatment',
    kind: PathwayFactKind.boolean,
  ),
  'antiresorptiveTreatmentOver12Months': PathwayFactDefinition(
    key: 'antiresorptiveTreatmentOver12Months',
    label:
        'Has the patient used the current antiresorptive treatment for more than 12 months?',
    kind: PathwayFactKind.boolean,
  ),
  'adheredToTheTreatment': PathwayFactDefinition(
    key: 'adheredToTheTreatment',
    label: 'Adhered to the treatment plan',
    kind: PathwayFactKind.boolean,
  ),
  'symptomaticFractureInLast12M': PathwayFactDefinition(
    key: 'symptomaticFractureInLast12M',
    label: 'Symptomatic fracture in the last 12 months',
    kind: PathwayFactKind.boolean,
  ),
  'multipleFractures': PathwayFactDefinition(
    key: 'multipleFractures',
    label: 'Two or more fractures',
    kind: PathwayFactKind.boolean,
  ),
  'lowBMD': PathwayFactDefinition(
    key: 'lowBMD',
    label: 'BMD T-score below -3.0 at any site',
    kind: PathwayFactKind.boolean,
  ),
  'priorMIorStroke': PathwayFactDefinition(
    key: 'priorMIorStroke',
    label: 'History of myocardial infarction or stroke',
    kind: PathwayFactKind.boolean,
  ),
  'sequencingFromDenosumab': PathwayFactDefinition(
    key: 'sequencingFromDenosumab',
    label: 'Sequencing from denosumab',
    kind: PathwayFactKind.boolean,
  ),
};

class LivePathwayTraceEntry {
  const LivePathwayTraceEntry({
    required this.nodeId,
    required this.pathwayId,
    required this.nodeType,
    this.matched,
    this.nextNodeId,
    this.actionsTriggered = const [],
  });

  final String nodeId;
  final String pathwayId;
  final String nodeType;
  final bool? matched;
  final String? nextNodeId;
  final List<Object?> actionsTriggered;

  factory LivePathwayTraceEntry.fromJson(Map<String, dynamic> json) =>
      LivePathwayTraceEntry(
        nodeId: json['nodeId']?.toString() ?? '',
        pathwayId: json['pathwayId']?.toString() ?? '',
        nodeType: json['nodeType']?.toString() ?? '',
        matched: json['matched'] as bool?,
        nextNodeId: json['nextNodeId']?.toString(),
        actionsTriggered: List<Object?>.from(
          json['actionsTriggered'] as List? ?? const [],
        ),
      );
}

sealed class LivePathwayResult {
  const LivePathwayResult({required this.pathwayId, required this.trace});
  final String pathwayId;
  final List<LivePathwayTraceEntry> trace;

  factory LivePathwayResult.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString();
    final trace = (json['trace'] as List? ?? const [])
        .map(
          (entry) => LivePathwayTraceEntry.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList(growable: false);
    if (status == 'question') {
      return PathwayQuestionStep(
        pathwayId: json['pathwayId']?.toString() ?? '',
        nodeId: json['nodeId']?.toString() ?? '',
        question: json['question']?.toString() ?? '',
        helperText: json['helperText']?.toString(),
        requiredFacts: List<String>.from(
          json['requiredFacts'] as List? ?? const [],
        ),
        trace: trace,
      );
    }
    if (status == 'complete') {
      return CompletedPathwayEvaluation(
        pathwayId: json['pathwayId']?.toString() ?? '',
        actions: (json['actions'] as List? ?? const [])
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList(growable: false),
        trace: trace,
      );
    }
    return PathwayRuntimeError(
      pathwayId: json['pathwayId']?.toString() ?? '',
      message: json['error'] is Map
          ? (json['error'] as Map)['message']?.toString() ??
                'The pathway could not be evaluated.'
          : json['error']?.toString() ?? 'The pathway could not be evaluated.',
      trace: trace,
    );
  }
}

class PathwayQuestionStep extends LivePathwayResult {
  const PathwayQuestionStep({
    required super.pathwayId,
    required this.nodeId,
    required this.question,
    this.helperText,
    required this.requiredFacts,
    required super.trace,
  });
  final String nodeId;
  final String question;
  final String? helperText;
  final List<String> requiredFacts;
}

class CompletedPathwayEvaluation extends LivePathwayResult {
  const CompletedPathwayEvaluation({
    required super.pathwayId,
    required this.actions,
    required super.trace,
  });
  final List<Map<String, Object?>> actions;
}

class PathwayRuntimeError extends LivePathwayResult {
  const PathwayRuntimeError({
    required super.pathwayId,
    required this.message,
    required super.trace,
  });
  final String message;
}
