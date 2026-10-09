import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/screens/clinician_case_screen.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:csi6224_patient_feedback/widgets/clinician_fact_summary.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:csi6224_patient_feedback/screens/patient_recommendation_screen.dart';
import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_presentation.dart';
import 'ui_polish_support.dart';

void main() {
  for (final concern in [true, false]) {
    test(
      'full P1 traversal always includes adherence concern=$concern in concise explanation',
      () {
        final fixture =
            jsonDecode(
                  File(
                    'test/fixtures/final_ui_evaluations.json',
                  ).readAsStringSync(),
                )['p1']['evaluation']
                as Map;
        for (final entry in fixture['trace'] as List) {
          if (entry['nodeId'] == 'ADHERENCE_CONCERN') {
            entry['matched'] = concern;
          }
        }
        final lines = recommendationExplanation(
          PathwayEvaluation.fromJson(Map<String, dynamic>.from(fixture)),
        );
        expect(
          lines,
          contains(
            concern
                ? 'There is a concern about treatment adherence.'
                : 'No treatment-adherence concern is confirmed.',
          ),
        );
        expect(lines.length, lessThanOrEqualTo(6));
      },
    );
  }
  test('P2 referral uses readable sentences without changing raw action', () {
    final action = PathwayAction.fromJson({
      'type': 'referral',
      'destination': 'SPECIALIST OR FRAGILE BONE CLINIC',
      'reason': 'Consider teriparatide.',
    });
    expect(
      action.description,
      'Refer the patient to a specialist or Fragile Bone Clinic. Consider teriparatide.',
    );
    expect(action.raw['destination'], 'SPECIALIST OR FRAGILE BONE CLINIC');
  });
  test('technical trace redirect result has no internal navigation text', () {
    final trace = ReasoningTraceEntry.fromJson({
      'nodeId': 'LEAF_REDIRECT_PATHWAY2',
      'pathwayId': 'PATHWAY1',
      'nodeType': 'leaf',
      'actionsTriggered': [
        {'type': 'pathwayRedirect', 'targetPathway': 'PATHWAY2'},
      ],
    });
    final presentation = clinicalTracePresentation(trace);
    expect(
      presentation.result,
      'The patient is currently taking osteoporosis treatment.',
    );
    expect(presentation.title, 'Current osteoporosis treatment');
  });
  testWidgets('care plan retains Follow-up section when none is specified', (
    tester,
  ) async {
    await mountPolish(
      tester,
      PatientRecommendationScreen(
        result: PatientApprovedResult(
          caseId: 'test',
          reviewedAt: DateTime(2026, 10, 9),
          lifestyleRecommendations: const [],
          careRecommendations: const [],
          clinicianMessage: 'Discuss with your clinician',
        ),
        onSignOut: () {},
      ),
    );
    expect(find.text('Follow-up'), findsOneWidget);
    expect(
      find.text('Follow-up has not been specified in this care plan.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'desktop review pairs recommendation with explanation and advice with decision',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationReviewScreen(
            caseId: 'evidence-case',
            repository: PolishRepository(approved: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Care Recommendation')).dy,
        tester.getTopLeft(find.text('Why this recommendation')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Current Patient Advice')).dy,
        tester.getTopLeft(find.text('Clinician Decision')).dy,
      );
      expect(find.text('Safety and discussion'), findsNothing);
    },
  );
  for (final pathway in ['p1', 'p2']) {
    testWidgets(
      '$pathway overview shows only answered current clinician facts in a collapsed read-only summary',
      (tester) async {
        final repo = PolishRepository(fixture: pathway);
        await mountPolish(
          tester,
          ClinicianCaseScreen(caseId: 'evidence-case', repository: repo),
        );
        expect(
          find.text('Clinician-confirmed pathway information'),
          findsOneWidget,
        );
        expect(find.text('Fracture site: Hip'), findsNothing);
        await tester.tap(find.text('Clinician-confirmed pathway information'));
        await tester.pumpAndSettle();
        expect(find.text('Fracture site: Hip'), findsOneWidget);
        expect(find.text('Minimal trauma fracture: Yes'), findsOneWidget);
        expect(
          find.textContaining('knownPoorMedicationAdherence'),
          findsNothing,
        );
        expect(find.textContaining('Cognitive impairment:'), findsNothing);
        expect(find.textContaining('Not provided'), findsNothing);
        expect(find.text('Edit'), findsNothing);
        if (pathway == 'p2') {
          expect(find.text('Adhered to treatment: Yes'), findsOneWidget);
        }
      },
    );
  }
  testWidgets(
    'summary maps canonical forearm and omits unknown and historical facts',
    (tester) async {
      await mountPolish(
        tester,
        const Scaffold(
          body: ClinicianFactSummary(
            facts: {
              'fractureSite': 'forearm',
              'eGFR': null,
              'adherenceConcern': false,
              'knownPoorMedicationAdherence': true,
              'cognitiveImpairment': true,
            },
          ),
        ),
      );
      await tester.tap(find.text('Clinician-confirmed pathway information'));
      await tester.pumpAndSettle();
      expect(find.text('Fracture site: Wrist / forearm'), findsOneWidget);
      expect(find.text('Treatment-adherence concern: No'), findsOneWidget);
      expect(find.textContaining('eGFR'), findsNothing);
      expect(find.textContaining('cognitive'), findsNothing);
    },
  );
  testWidgets('renal confirmation explains shared pre-routing eligibility', (
    tester,
  ) async {
    await mountPolish(
      tester,
      PathwayQuestionScreen(
        caseId: 'evidence-case',
        repository: PolishRepository(node: 'RENAL_DYSFUNCTION'),
      ),
    );
    expect(
      find.text(
        'This kidney-function check is part of the shared eligibility flow before Pathway 1 or Pathway 2 is selected.',
      ),
      findsOneWidget,
    );
  });
}
