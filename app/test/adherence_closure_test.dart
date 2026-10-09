import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:csi6224_patient_feedback/utils/recommendation_presentation.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'ui_polish_support.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:csi6224_patient_feedback/widgets/fracture_site_field.dart';
import 'live_pathway_contract_test.dart' show clinicianCase;

Future<({MockAppRepository repository, String caseId})> adherenceCase() async {
  final setup = await clinicianCase();
  for (final entry in {
    'eGFR': true,
    'osteoporosisTreatmentStatus': false,
    'frailtyResidentialOrLimitedLifeExpectancy': false,
  }.entries) {
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: entry.key,
      value: entry.value,
    );
  }
  return setup;
}

void main() {
  testWidgets(
    'retired component facts are explicitly reference-only in the collapsed audit',
    (tester) async {
      await mountPolish(
        tester,
        RecommendationReviewScreen(
          caseId: 'evidence-case',
          repository: PolishRepository(),
        ),
      );
      expect(find.textContaining('Historical reference:'), findsNothing);
      await tester.ensureVisible(find.text('View technical trace'));
      await tester.tap(find.text('View technical trace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Historical reference:'), findsNWidgets(2));
    },
  );
  for (final site in ['hand', 'ankle']) {
    testWidgets(
      'excluded $site stays ineligible through the real mock UI journey',
      (tester) async {
        final setup = await clinicianCase(confirmEligibility: false);
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'minimalTraumaFracture',
          value: 'yes',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PathwayQuestionScreen(
              caseId: setup.caseId,
              repository: setup.repository,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        expect(find.text('Other eligible site'), findsNothing);
        expect(find.text(site == 'hand' ? 'Hand' : 'Ankle'), findsNothing);
        await tester.tap(
          find.text('Excluded site — hand, foot, face, or ankle').last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(site == 'hand' ? 'Hand' : 'Ankle').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Hand, foot, face, and ankle fractures are not eligible for the general minimal-trauma-fracture pathway.',
          ),
          findsWidgets,
        );
        final c = await setup.repository.fetchClinicalCase(setup.caseId);
        expect(c.clinicianFacts['fractureSite'], site);
        expect(c.evaluation, isNull);
        expect(
          find.text('This fracture is not eligible for Pathway 1.'),
          findsNothing,
        );
      },
    );
  }
  test(
    'history models remain readable but never serialize old components as active authority',
    () {
      final input = Pathway1ClinicianInput.fromJson({
        'knownPoorMedicationAdherence': true,
        'cognitiveImpairment': false,
      });
      expect(input.knownPoorMedicationAdherence, true);
      expect(input.cognitiveImpairment, false);
      expect(input.adherenceConcern, isNull);
      expect(
        input.toJson().containsKey('knownPoorMedicationAdherence'),
        isFalse,
      );
      expect(
        input.toEvaluatorFacts().containsKey('cognitiveImpairment'),
        isFalse,
      );
    },
  );
  test(
    'current Yes/No explanations and historical trace labels keep their meanings separate',
    () {
      for (final value in [true, false]) {
        final current = PathwayEvaluation.fromJson({
          'pathwayId': 'PATHWAY1',
          'contractVersion': 'songyi-p1p2-20261009-adherence',
          'trace': [
            {
              'pathwayId': 'PATHWAY1',
              'nodeId': 'ADHERENCE_CONCERN',
              'nodeType': 'decision',
              'matched': value,
            },
          ],
        });
        expect(recommendationExplanation(current), [
          value
              ? 'There is a concern about treatment adherence.'
              : 'No treatment-adherence concern is confirmed.',
        ]);
        expect(
          clinicalTracePresentation(current.trace.single).details.single,
          contains('Treatment-adherence concern = Yes'),
        );
      }
      const old = ReasoningTraceEntry(
        ruleId: 'ADHERENCE_CONCERN',
        matched: true,
        reason: '',
        pathwayId: 'PATHWAY1',
        nodeType: 'decision',
        contractVersion: 'songyi-p1p2-20261009-care',
      );
      expect(
        clinicalTracePresentation(old).title,
        'Historical adherence-component decision',
      );
      expect(
        clinicalTracePresentation(old).details.single,
        contains('Fresh adherence-concern confirmation'),
      );
    },
  );
  for (final concern in [true, false]) {
    test(
      'mock consumes explicit aggregate $concern without components',
      () async {
        final setup = await adherenceCase();
        await setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'adherenceConcern',
          value: concern,
        );
        final result = await setup.repository.evaluatePathway(
          caseId: setup.caseId,
        );
        if (concern) {
          expect(result, isA<CompletedPathwayEvaluation>());
        } else {
          expect(
            (result as PathwayQuestionStep).nodeId,
            'DXA_SCAN_AVAILABILITY',
          );
        }
      },
    );
  }
  testWidgets('missing adherence asks one unset question and blocks Next', (
    tester,
  ) async {
    final setup = await adherenceCase();
    await tester.pumpWidget(
      MaterialApp(
        home: PathwayQuestionScreen(
          caseId: setup.caseId,
          repository: setup.repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Is there concern about the patient's ability to follow the treatment plan?",
      ),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
    expect(find.text('Known poor medication adherence'), findsNothing);
    expect(find.text('Cognitive impairment affecting adherence'), findsNothing);
    expect(find.text('More information is required.'), findsOneWidget);
    final control = tester.widget<DropdownButtonFormField<bool>>(
      find.byType(DropdownButtonFormField<bool>),
    );
    expect(control.initialValue, isNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(
      (await setup.repository.fetchClinicalCase(
        setup.caseId,
      )).clinicianFacts.containsKey('adherenceConcern'),
      isFalse,
    );
  });
  testWidgets('excluded fracture message applies to shared general entry scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FractureSiteField(value: 'ankle', onChanged: (_) {}),
        ),
      ),
    );
    expect(
      find.text(
        'Hand, foot, face, and ankle fractures are not eligible for the general minimal-trauma-fracture pathway.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Pathway 1'), findsNothing);
  });
}
