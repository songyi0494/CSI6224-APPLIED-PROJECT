class PathwayEvaluation {
  const PathwayEvaluation({
    required this.pathway,
    required this.decision,
    required this.actions,
    required this.trace,
    this.missingInputs = const [],
    this.unsafeInputs = const [],
    this.warning,
  });

  final String pathway;
  final String decision;
  final List<PathwayAction> actions;
  final List<String> trace;
  final List<String> missingInputs;
  final List<String> unsafeInputs;
  final String? warning;

  factory PathwayEvaluation.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'];
    final rawTrace = json['trace'];
    return PathwayEvaluation(
      pathway: json['pathway']?.toString() ?? 'unknown',
      decision: json['decision']?.toString() ?? 'no_action',
      actions: rawActions is List
          ? rawActions
              .whereType<Map>()
              .map(
                (item) =>
                    PathwayAction.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
          : const [],
      trace: rawTrace is List
          ? rawTrace.map((item) => item.toString()).toList()
          : const [],
      missingInputs: const [],
    );
  }
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
    return json.toString();
  }
}
