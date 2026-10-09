import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:csi6224_patient_feedback/widgets/pathway_action_view.dart';

void main() {
  test('renal trace uses Boolean threshold condition and recorded branch', () {
    final display = clinicalTracePresentation(ReasoningTraceEntry.fromJson({
      'nodeId': 'RENAL_DYSFUNCTION', 'nodeType': 'decision',
      'pathwayId': 'PATHWAY1', 'matched': true,
      'contractVersion': 'songyi-p1p2-20261008',
      'nextNodeId': 'ON_OSTEOPOROSIS_TREATMENT',
    }));
    expect(display.title, contains('eGFR'));
    expect(display.details.single, contains('≥30 mL/min = Yes'));
    expect(display.result, 'Condition met.');
    expect(display.implication, contains('currently on osteoporosis treatment'));
  });

  testWidgets('care plans remain separate from medication alternatives', (tester) async {
    final action = PathwayAction.fromJson({
      'type': 'actionOptions', 'options': [
        [
          {'type': 'treatmentOptions', 'options': [
            {'type': 'medication', 'medication': 'Example A', 'dose': '5mg'},
            {'type': 'medication', 'medication': 'Example B', 'dose': '60mg'},
          ]},
          {'type': 'followUp', 'destination': 'GP'},
        ],
        [{'type': 'referral', 'destination': 'SPECIALIST'}],
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: PathwayActionView(action: action)))));
    expect(find.text('Care plan 1'), findsOneWidget);
    expect(find.text('Care plan 2'), findsOneWidget);
    expect(find.text('Medication alternatives'), findsOneWidget);
    expect(find.text('Example A'), findsOneWidget);
    expect(find.text('Example B'), findsOneWidget);
    expect(find.text('Follow up with GP.'), findsOneWidget);
    expect(find.text('Option 1:'), findsNothing);
  });
}
