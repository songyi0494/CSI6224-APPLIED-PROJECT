class ReasoningTraceEntry {
  const ReasoningTraceEntry({
    required this.ruleId,
    required this.matched,
    required this.reason,
    this.input = const {},
  });
  final String ruleId, reason;
  final bool? matched;
  final Map<String, Object?> input;
  factory ReasoningTraceEntry.fromJson(Map<String, dynamic> j) =>
      ReasoningTraceEntry(
        ruleId: (j['rule_id'] ?? j['nodeId'] ?? 'unknown').toString(),
        matched: j['matched'] as bool?,
        reason: (j['reason'] ?? _liveReason(j)).toString(),
        input: Map<String, Object?>.from((j['input'] as Map?) ?? const {}),
      );

  static String _liveReason(Map<String, dynamic> json) {
    final next = json['nextNodeId'];
    final type = json['nodeType']?.toString() ?? 'node';
    return next == null ? 'Reached $type.' : 'Traversal continued to $next.';
  }
}

class PathwayEvaluation {
  const PathwayEvaluation({
    required this.pathway,
    required this.decision,
    required this.actions,
    required this.trace,
    required this.ruleVersion,
    required this.routingReason,
    this.pathwayRevision,
    this.investigationRevision,
    this.missingInputs = const [],
    this.warnings = const [],
  });
  final String? pathway;
  final int? pathwayRevision, investigationRevision;
  final String decision, ruleVersion, routingReason;
  final List<PathwayAction> actions;
  final List<ReasoningTraceEntry> trace;
  final List<String> missingInputs, warnings;
  bool get canApprove =>
      (pathway == 'PATHWAY1' || pathway == 'PATHWAY2') &&
      (decision == 'action_taken' || decision == 'complete') &&
      missingInputs.isEmpty &&
      actions.isNotEmpty;
  factory PathwayEvaluation.fromJson(
    Map<String, dynamic> j,
  ) => PathwayEvaluation(
    pathway: (j['pathway'] ?? j['pathwayId']) as String?,
    decision: (j['decision'] ?? j['status'] ?? 'complete').toString(),
    ruleVersion: (j['rule_version'] ?? 'evaluate_pathway-v12').toString(),
    routingReason: (j['routing_reason'] ?? 'Backend-driven pathway traversal')
        .toString(),
    pathwayRevision: (j['pathwayRevision'] as num?)?.toInt(),
    investigationRevision: (j['investigationRevision'] as num?)?.toInt(),
    actions: (j['actions'] as List? ?? const [])
        .map((a) => PathwayAction.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList(),
    trace: (j['trace'] as List? ?? const [])
        .map(
          (a) =>
              ReasoningTraceEntry.fromJson(Map<String, dynamic>.from(a as Map)),
        )
        .toList(),
    missingInputs: List<String>.from(j['missing_inputs'] as List? ?? const []),
    warnings: List<String>.from(j['warnings'] as List? ?? const []),
  );
}

class PathwayAction {
  const PathwayAction({
    required this.type,
    required this.description,
    required this.raw,
  });

  final String type;
  final String description;
  final Map<String, Object?> raw;

  factory PathwayAction.fromJson(Map<String, dynamic> json) {
    return PathwayAction(
      type: json['type']?.toString() ?? 'action',
      description: _describe(json),
      raw: Map<String, Object?>.from(json),
    );
  }

  static String _describe(Map<String, dynamic> json) {
    if (json['recommendation'] != null) {
      return json['recommendation'].toString();
    }
    if (json['medication'] != null) {
      final parts = [
        json['medication'],
        json['dose'],
        json['route'],
        json['frequency'],
      ].where((value) => value != null && value.toString().isNotEmpty);
      return parts.join(', ');
    }
    if (json['destination'] != null) {
      final reason = json['reason'] == null ? '' : ': ${json['reason']}';
      return 'Refer to ${json['destination']}$reason';
    }
    if (json['action'] != null) {
      return json['action'].toString();
    }
    if (json['instruction'] != null) {
      return json['instruction'].toString();
    }
    if (json['targetPathway'] != null) {
      return 'Redirect to ${json['targetPathway']}';
    }
    if (json['options'] is List) {
      return 'Review treatment options';
    }
    return 'Clinical action requires review.';
  }
}
