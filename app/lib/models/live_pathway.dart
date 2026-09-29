enum PathwayFactKind { boolean, number }

class PathwayFactDefinition {
  const PathwayFactDefinition({
    required this.key,
    required this.label,
    required this.kind,
    this.unit,
    this.wholeNumber = false,
    this.allowNegative = false,
  });

  final String key;
  final String label;
  final PathwayFactKind kind;
  final String? unit;
  final bool wholeNumber;
  final bool allowNegative;
}

/// Presentation/type metadata absent from evaluate_pathway v12.
/// Keys and JSON types are an explicit mirror of the deployed P1/P2 rules.
const pathwayFactRegistry = <String, PathwayFactDefinition>{
  'eGFR': PathwayFactDefinition(
    key: 'eGFR',
    label: 'eGFR',
    kind: PathwayFactKind.number,
    unit: 'mL/min',
  ),
  'osteoporosisTreatmentStatus': PathwayFactDefinition(
    key: 'osteoporosisTreatmentStatus',
    label: 'Currently on osteoporosis treatment',
    kind: PathwayFactKind.boolean,
  ),
  'liveInResidentialCare': PathwayFactDefinition(
    key: 'liveInResidentialCare',
    label: 'Lives in residential care',
    kind: PathwayFactKind.boolean,
  ),
  'clinicalFrailtyScore': PathwayFactDefinition(
    key: 'clinicalFrailtyScore',
    label: 'Clinical Frailty Scale score',
    kind: PathwayFactKind.number,
    wholeNumber: true,
  ),
  'lifeExpectancy': PathwayFactDefinition(
    key: 'lifeExpectancy',
    label: 'Life expectancy',
    kind: PathwayFactKind.number,
    unit: 'years',
  ),
  'knownPoorMedicationAdherence': PathwayFactDefinition(
    key: 'knownPoorMedicationAdherence',
    label: 'Known poor medication adherence',
    kind: PathwayFactKind.boolean,
  ),
  'cognitiveImpairment': PathwayFactDefinition(
    key: 'cognitiveImpairment',
    label: 'Cognitive impairment affecting adherence',
    kind: PathwayFactKind.boolean,
  ),
  'testAvailability': PathwayFactDefinition(
    key: 'testAvailability',
    label: 'BMD DXA available or completed within two years',
    kind: PathwayFactKind.boolean,
  ),
  'femoralNeckTscore': PathwayFactDefinition(
    key: 'femoralNeckTscore',
    label: 'Femoral neck T-score',
    kind: PathwayFactKind.number,
    allowNegative: true,
  ),
  'hipTscore': PathwayFactDefinition(
    key: 'hipTscore',
    label: 'Hip T-score',
    kind: PathwayFactKind.number,
    allowNegative: true,
  ),
  'lumbarSpineTscore': PathwayFactDefinition(
    key: 'lumbarSpineTscore',
    label: 'Lumbar spine T-score',
    kind: PathwayFactKind.number,
    allowNegative: true,
  ),
  'hipVertebralOrMultipleFracturesInLast24M': PathwayFactDefinition(
    key: 'hipVertebralOrMultipleFracturesInLast24M',
    label: 'Hip, vertebral, or multiple fractures in the last 24 months',
    kind: PathwayFactKind.boolean,
  ),
  'recentFractureWithin2Y': PathwayFactDefinition(
    key: 'recentFractureWithin2Y',
    label: 'Recent fracture within two years',
    kind: PathwayFactKind.boolean,
  ),
  'historyOf2orMoreFractures': PathwayFactDefinition(
    key: 'historyOf2orMoreFractures',
    label: 'History of two or more fractures',
    kind: PathwayFactKind.boolean,
  ),
  'clinicalRiskFactors': PathwayFactDefinition(
    key: 'clinicalRiskFactors',
    label: 'Additional clinical risk factors',
    kind: PathwayFactKind.boolean,
  ),
  'FRAX10YmajorOsteoporoticFractureRiskPercent': PathwayFactDefinition(
    key: 'FRAX10YmajorOsteoporoticFractureRiskPercent',
    label: 'FRAX 10-year major osteoporotic fracture risk',
    kind: PathwayFactKind.number,
    unit: '%',
  ),
  'FRAX10YmajorHipFractureRiskPercent': PathwayFactDefinition(
    key: 'FRAX10YmajorHipFractureRiskPercent',
    label: 'FRAX 10-year hip fracture risk',
    kind: PathwayFactKind.number,
    unit: '%',
  ),
  'antiresorptiveTreatmentStatus': PathwayFactDefinition(
    key: 'antiresorptiveTreatmentStatus',
    label: 'Currently on antiresorptive treatment',
    kind: PathwayFactKind.boolean,
  ),
  'antiresorptiveTreatmentDuration': PathwayFactDefinition(
    key: 'antiresorptiveTreatmentDuration',
    label: 'Antiresorptive treatment for 12 months or longer',
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
      message:
          json['error']?.toString() ?? 'The pathway could not be evaluated.',
      trace: trace,
    );
  }
}

class PathwayQuestionStep extends LivePathwayResult {
  const PathwayQuestionStep({
    required super.pathwayId,
    required this.nodeId,
    required this.question,
    required this.requiredFacts,
    required super.trace,
  });
  final String nodeId;
  final String question;
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
