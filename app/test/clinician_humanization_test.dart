import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:csi6224_patient_feedback/utils/medication_display.dart';
import 'package:csi6224_patient_feedback/widgets/pathway_action_view.dart';
import 'clinician_ste_summary_test.dart' as ste;
import 'widget_test.dart' as support;

// Supply the live-shaped read response directly. The existing mock writer uses
// a legacy shape that drops nodeType, triggered actions and unknown audit fields.
class ResponseRepository extends MockAppRepository {
  ResponseRepository(this.original)
    : super(evaluate: (_) async => PathwayEvaluation.fromJson(original));
  final Map<String, dynamic> original;
  @override
  Future<ClinicalCase> fetchClinicalCase(String id) async {
    final base = await super.fetchClinicalCase(id);
    return ClinicalCase(
      id: base.id,
      patientId: base.patientId,
      patientName: base.patientName,
      input: base.input,
      status: base.status,
      revision: base.revision,
      updatedAt: base.updatedAt,
      pathway: base.pathway,
      evaluation: PathwayEvaluation.fromJson(original),
      clinicianInput: base.clinicianInput,
      clinicianFacts: base.clinicianFacts,
      pathwayRevision: base.pathwayRevision,
      evaluationId: base.evaluationId,
      assignedClinicianId: base.assignedClinicianId,
      questionnaireResponseId: base.questionnaireResponseId,
    );
  }
}

Map<String, dynamic> response(String pathway, {bool metadata = false}) {
  final actions = [
    {
      'type': 'actionOptions',
      'options': [
        [
          {
            'type': 'treatmentOptions',
            'options': [
              {
                'type': 'medication',
                'medication': 'Example A',
                'dose': '5mg',
                'route': 'oral',
                'frequency': 'weekly',
                'duration': '3 years',
              },
              {
                'type': 'medication',
                'medication': 'Example B',
                'dose': '60mg',
                'route': 'subcut',
                'frequency': '6 monthly',
              },
            ],
          },
          {'type': 'followUp', 'destination': 'GP', 'when': 'In 4 weeks'},
          {
            'type': 'review',
            'instruction': 'Reassess fracture risk after 5 years.',
          },
        ],
        [
          {
            'type': 'referral',
            'destination': 'SPECIALIST',
            'when': 'If assistance is needed.',
            'reason': 'Recorded safety reason.',
          },
          {
            'type': 'restartDenosumab',
            'timing': 'Start 3 months post last dose.',
            'instruction': 'Recorded conditional restart instruction.',
          },
        ],
      ],
    },
  ];
  return {
    'status': 'complete',
    'pathwayId': pathway,
    if (metadata) 'rule_version': 'recorded-version-7',
    if (metadata) 'routing_reason': 'Recorded routing explanation.',
    'provenance_extra': {'unrecognised_original_field': 'retain exactly'},
    'warnings': ['Recorded safety warning.'],
    'actions': actions,
    'trace': [
      {
        'nodeId': 'UNMAPPED_FIRST_CHECK',
        'pathwayId': pathway,
        'nodeType': 'decision',
        'matched': true,
        'actionsTriggered': [],
      },
      {
        'nodeId': 'LEAF_REDIRECT_PATHWAY2',
        'pathwayId': 'PATHWAY1',
        'nodeType': 'leaf',
        'actionsTriggered': [
          {'type': 'pathwayRedirect', 'targetPathway': 'PATHWAY2'},
        ],
      },
      {
        'nodeId': 'UNMAPPED_FINAL_OUTCOME',
        'pathwayId': pathway,
        'nodeType': 'leaf',
        'actionsTriggered': actions,
      },
    ],
  };
}

void main() {
  testWidgets('recorded transfer destinations remain readable and complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PathwayActionView(
            action: PathwayAction.fromJson({
              'type': 'pathwayRedirect',
              'targetPathway': 'PATHWAY4',
            }),
            compactMedications: true,
          ),
        ),
      ),
    );
    expect(find.text('Continue to Pathway 4.'), findsOneWidget);
  });
  test('formatter preserves meanings and only marks absent duration', () {
    for (final dose in ['5mg', '35mg', '60mg']) {
      expect(
        medicationDisplayValue('dose', dose),
        dose.replaceFirst('mg', ' mg'),
      );
    }
    expect(medicationDisplayValue('route', 'subcut'), 'Subcutaneous');
    expect(medicationDisplayValue('frequency', '6 monthly'), 'Every 6 months');
    expect(medicationDisplayValue('duration', null), 'Not specified');
    expect(medicationDisplayValue('duration', ''), '');
    expect(medicationDisplayValue('duration', '18–24 months'), '18–24 months');
    expect(
      medicationDisplayValue('dose', 'Recorded conditional dose'),
      'Recorded conditional dose',
    );
  });
  test('provenance distinguishes absent metadata from parser defaults', () {
    final original = response('PATHWAY1');
    final evaluation = PathwayEvaluation.fromJson(original);
    expect(evaluation.recordedRuleVersion, isNull);
    expect(evaluation.recordedRoutingReason, isNull);
    expect(evaluation.recordedData, original);
    expect(
      evaluation.trace.last.recordedData,
      (original['trace'] as List).last,
    );
    expect(evaluation.canApprove, isTrue);
  });
  for (final pathway in ['PATHWAY1', 'PATHWAY2']) {
    for (final size in [const Size(1440, 900), const Size(360, 800)]) {
      testWidgets('$pathway clinical actions and exact audit at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final original = response(pathway, metadata: pathway == 'PATHWAY2');
        final repo = ResponseRepository(original);
        final id = await ste.prepare(repo);
        await repo.completePathway1ClinicianInput(
          assessment: await repo.fetchClinicalCase(id),
          input: support.completePathway1ClinicianInput,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RecommendationReviewScreen(caseId: id, repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('• Recorded safety warning.'), findsOneWidget);
        expect(find.textContaining('5 mg'), findsOneWidget);
        expect(find.textContaining('Subcutaneous'), findsOneWidget);
        expect(find.textContaining('Every 6 months'), findsOneWidget);
        expect(find.textContaining('Not specified'), findsOneWidget);
        await ste.open(tester, find.byKey(const ValueKey('decision-trace')));
        expect(find.textContaining('Rule ID:'), findsNothing);
        expect(find.textContaining('evaluate_pathway-v12'), findsNothing);
        expect(
          find.textContaining('Backend-driven pathway traversal'),
          findsNothing,
        );
        expect(find.textContaining('actionsTriggered'), findsNothing);
        expect(find.textContaining('UNMAPPED_FINAL_OUTCOME'), findsNothing);
        expect(find.text('Terminal outcome recorded.'), findsNWidgets(2));
        expect(
          find.textContaining('Recorded conditional restart instruction.'),
          findsNWidgets(2),
        );
        expect(
          find.textContaining('Start 3 months post last dose.'),
          findsNWidgets(2),
        );
        expect(
          find.textContaining('If assistance is needed.'),
          findsNWidgets(2),
        );
        final steps = [
          for (var i = 0; i < 3; i++)
            tester.getTopLeft(find.byKey(ValueKey('trace-step-$i'))).dy,
        ];
        expect(steps[0], lessThan(steps[1]));
        expect(steps[1], lessThan(steps[2]));
        expect(find.text('Technical audit details'), findsNothing);
        expect(
          find.byKey(const ValueKey('evaluation-technical-audit')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('recorded-evaluation-json')),
          findsNothing,
        );
        final savedEvaluation = (await repo.fetchClinicalCase(id)).evaluation!;
        expect(savedEvaluation.recordedData, original);
        expect(
          savedEvaluation.trace.last.recordedData,
          (original['trace'] as List).last,
        );
        expect(
          savedEvaluation.recordedRuleVersion,
          pathway == 'PATHWAY2' ? 'recorded-version-7' : null,
        );
        expect(
          savedEvaluation.recordedRoutingReason,
          pathway == 'PATHWAY2' ? 'Recorded routing explanation.' : null,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
