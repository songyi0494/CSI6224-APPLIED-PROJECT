import 'dart:io';
import 'dart:ui' as ui;

import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/screens/clinician_case_screen.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as support;

Future<void> capture(GlobalKey key, String name) async {
  const directory = String.fromEnvironment('STE_SCREENSHOT_DIR');
  if (directory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
}

Future<String> prepare(MockAppRepository repo) async {
  await support.signIn(repo, 'patient@example.test');
  await repo.submitQuestionnaireResponse(
    answers: const {
      'postmenopausal': 'Yes',
      'adultFractureHistory': 'Yes',
      'fractureSite': 'Hip',
      'smoking': 'No',
      'alcohol': 'No',
      'dietaryDairyServings': 2,
    },
  );
  final assessment = (await repo.fetchClinicalCases()).single;
  await repo.submitAssessment(
    id: assessment.id,
    revision: assessment.revision,
    input: assessment.input,
  );
  await support.signIn(repo, 'clinician@example.test');
  return assessment.id;
}

Future<void> open(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    const directory = String.fromEnvironment('STE_SCREENSHOT_DIR');
    if (directory.isEmpty) return;
    const fonts = String.fromEnvironment('STE_FLUTTER_FONT_DIR');
    if (fonts.isEmpty) {
      throw StateError(
        'STE_FLUTTER_FONT_DIR is required for readable screenshots.',
      );
    }
    for (final family in ['Roboto', 'Segoe UI']) {
      final loader = FontLoader(family);
      loader.addFont(
        File(
          '$fonts/roboto-regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '$fonts/materialicons-regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
    await icons.load();
  });
  for (final size in [const Size(360, 800), const Size(1440, 900)]) {
    testWidgets('summary, full answers and all trace evidence fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = support.repository();
      final id = await prepare(repo);
      final overviewKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: overviewKey,
          child: MaterialApp(
            theme: ThemeData(
              platform: size.width < 600
                  ? TargetPlatform.android
                  : TargetPlatform.windows,
            ),
            home: ClinicianCaseScreen(caseId: id, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clinical Summary'), findsOneWidget);
      expect(
        find.text('Adult fracture history (patient report): Yes'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Minimal-trauma fracture (patient report)'),
        findsNothing,
      );
      await tester.runAsync(
        () => capture(overviewKey, 'overview-${size.width.toInt()}'),
      );
      expect(
        tester.getTopLeft(find.text('Clinical Summary')).dy,
        lessThan(
          tester.getTopLeft(find.text('Patient-Reported Questionnaire')).dy,
        ),
      );
      expect(find.text('Hip'), findsNothing);
      expect(find.text('Enter investigations'), findsOneWidget);
      await open(
        tester,
        find.byKey(const ValueKey('patient-questionnaire-details')),
      );
      expect(find.text('Hip'), findsOneWidget);
      expect(find.textContaining('Assessment revision '), findsOneWidget);
      expect(tester.takeException(), isNull);

      await repo.completePathway1ClinicianInput(
        assessment: await repo.fetchClinicalCase(id),
        input: support.completePathway1ClinicianInput,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final reviewKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: reviewKey,
          child: MaterialApp(
            theme: ThemeData(
              platform: size.width < 600
                  ? TargetPlatform.android
                  : TargetPlatform.windows,
            ),
            home: RecommendationReviewScreen(caseId: id, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => capture(reviewKey, 'review-${size.width.toInt()}'),
      );
      final care = tester.getTopLeft(find.text('Care Recommendation'));
      final advice = tester.getTopLeft(find.text('Common Advice'));
      if (size.width >= 1000) {
        expect(advice.dx, greaterThan(care.dx + 600));
        expect(advice.dy, closeTo(care.dy, 1));
        expect(
          tester.getSize(find.byKey(const ValueKey('review-content'))).width,
          closeTo(1280, 1),
        );
      } else {
        expect(advice.dy, greaterThan(care.dy));
      }
      expect(
        tester.getTopLeft(find.text('Clinical Summary')).dy,
        lessThan(tester.getTopLeft(find.text('Care Recommendation')).dy),
      );
      expect(
        find.text(
          'Hip, spine or multiple fractures in the last 24 months (clinician fact): Yes',
        ),
        findsOneWidget,
      );
      expect(find.text('Rule ID: ENTRY'), findsNothing);
      await open(tester, find.byKey(const ValueKey('decision-trace')));
      final saved = await repo.fetchClinicalCase(id);
      for (var i = 0; i < saved.evaluation!.trace.length; i++) {
        final trace = saved.evaluation!.trace[i];
        expect(find.byKey(ValueKey('trace-step-$i')), findsOneWidget);
        expect(find.text('Rule ID: ${trace.ruleId}'), findsNothing);
      }
      expect(find.text('Technical audit details'), findsNothing);
      expect(find.text('eGFR: 54 mL/min'), findsOneWidget);
      expect(
        find.text('Consider commencement of osteoanabolic therapy'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('warnings and missing inputs stay visible with trace closed', (
    tester,
  ) async {
    final repo = MockAppRepository(
      evaluate: (_) async => const PathwayEvaluation(
        pathway: 'PATHWAY1',
        decision: 'manual_review',
        actions: [],
        trace: [],
        ruleVersion: 'fixture',
        routingReason: 'Recorded routing reason',
        warnings: ['Recorded safety warning'],
        missingInputs: ['eGFR'],
      ),
    );
    final id = await prepare(repo);
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
    expect(find.text('• Recorded safety warning'), findsOneWidget);
    expect(find.text('• Kidney function (eGFR)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Approve'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Withhold'), findsOneWidget);
    await open(tester, find.byKey(const ValueKey('decision-trace')));
    expect(
      find.text('No decision trace is available for this result.'),
      findsOneWidget,
    );
  });

  for (final size in [const Size(1440, 900), const Size(360, 800)]) {
    testWidgets('two care plans retain full medication and safety text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockAppRepository(
        evaluate: (_) async => PathwayEvaluation(
          pathway: 'PATHWAY1',
          decision: 'action_taken',
          trace: const [],
          ruleVersion: 'layout-fixture',
          routingReason: 'Synthetic layout fixture',
          actions: [
            PathwayAction.fromJson({
              'type': 'actionOptions',
              'options': [
                [
                  {
                    'type': 'treatmentOptions',
                    'options': [
                      {
                        'type': 'medication',
                        'medication': 'Synthetic medication A',
                        'dose':
                            '5 mg with the full recorded administration instructions',
                        'route': 'Oral',
                        'frequency': 'Weekly',
                        'duration': '3 years',
                        'warnings':
                            'Recorded safety warning; do not combine alternatives.',
                      },
                      {
                        'type': 'medication',
                        'medication': 'Synthetic medication B',
                        'dose': '60 mg',
                        'route': 'Subcutaneous',
                        'frequency': 'Every 6 months',
                        'duration': 'Recorded duration',
                      },
                    ],
                  },
                  {
                    'type': 'followUp',
                    'destination': 'GP',
                    'when': 'In 4 weeks',
                  },
                ],
                [
                  {
                    'type': 'medication',
                    'medication': 'Synthetic medication C',
                    'dose': 'Recorded dose',
                    'route': 'Recorded route',
                    'frequency': 'Recorded frequency',
                    'duration': 'Recorded duration',
                  },
                  {
                    'type': 'referral',
                    'destination': 'SPECIALIST',
                    'reason': 'Recorded referral reason',
                  },
                ],
              ],
            }),
          ],
        ),
      );
      final id = await prepare(repo);
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
      for (final label in [
        'Care plan 1',
        'Care plan 2',
        'Synthetic medication A',
        'Synthetic medication B',
        'Synthetic medication C',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.textContaining(
          '5 mg with the full recorded administration instructions',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Recorded safety warning; do not combine alternatives.',
        ),
        findsOneWidget,
      );
      expect(find.text('Follow up with GP\nWhen: In 4 weeks'), findsOneWidget);
      expect(
        find.text('Refer to Specialist: Recorded referral reason'),
        findsOneWidget,
      );
      final med = find.text('Synthetic medication A');
      final medText = tester.widget<Text>(med);
      expect(medText.maxLines, isNull);
      expect(medText.overflow, isNot(TextOverflow.ellipsis));
      final style = DefaultTextStyle.of(
        tester.element(med),
      ).style.merge(medText.style);
      expect(style.fontSize, greaterThanOrEqualTo(14));
      expect(tester.takeException(), isNull);
    });
  }

  for (final decision in [
    ClinicalCaseStatus.approved,
    ClinicalCaseStatus.withheld,
  ]) {
    testWidgets(
      '$decision keeps message, Common Advice and patient release gates',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = support.repository();
        final id = await prepare(repo);
        await repo.claimClinicalCase(id);
        await repo.saveCaseInvestigations(
          caseId: id,
          vitaminDLevel: 55,
          ionisedCalcium: 1.2,
          bodyWeightKg: 70,
          expectedRevision: 0,
        );
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
        await open(
          tester,
          find.widgetWithText(
            ChoiceChip,
            decision == ClinicalCaseStatus.approved ? 'Approve' : 'Withhold',
          ),
        );
        await open(tester, find.text('Save decision'));
        expect((await repo.fetchClinicalCase(id)).status, isNot(decision));
        expect(
          find.text(
            decision == ClinicalCaseStatus.approved
                ? 'Enter the clinician message for the patient.'
                : 'Enter the reason for withholding this recommendation.',
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.byType(TextField),
          'Recorded clinician message.',
        );
        await open(tester, find.text('Save decision'));
        if (decision == ClinicalCaseStatus.approved) {
          expect(
            find.text(
              'Generate current Common Advice before approving this result.',
            ),
            findsOneWidget,
          );
          expect((await repo.fetchClinicalCase(id)).status, isNot(decision));
          await open(tester, find.text('Generate Common Advice'));
          expect(
            find.text('Clinician-reviewed Vitamin D advice.'),
            findsOneWidget,
          );
          await open(tester, find.text('Save decision'));
        }
        final saved = await repo.fetchClinicalCase(id);
        expect(saved.status, decision);
        expect(saved.decisionNotes, 'Recorded clinician message.');
        expect(find.text('The clinician approved this result.'), findsNothing);
        expect(find.text('The clinician withheld this result.'), findsNothing);
        expect(
          find.text('Common Advice: Available for clinician review.'),
          findsNothing,
        );
        expect(
          find.text(
            decision == ClinicalCaseStatus.approved ? 'Approved' : 'Withheld',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('saved-decision-status')),
            matching: find.text(
              decision == ClinicalCaseStatus.approved ? 'Approved' : 'Withheld',
            ),
          ),
          findsOneWidget,
        );
        final note = tester.widget<SelectableText>(
          find.widgetWithText(SelectableText, 'Recorded clinician message.'),
        );
        expect(note.data, saved.decisionNotes);
        expect(note.style!.fontSize, greaterThanOrEqualTo(16));
        expect(note.style!.fontWeight, FontWeight.w600);
        expect(
          tester.getTopLeft(find.text('Return to Work Queue')).dy,
          closeTo(
            tester.getTopLeft(find.text('Back to Patient Overview')).dy,
            1,
          ),
        );
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(
          find.text(
            decision == ClinicalCaseStatus.approved ? 'Approved' : 'Withheld',
          ),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.text('Common Advice')).dy,
          greaterThan(tester.getTopLeft(find.text('Care Recommendation')).dy),
        );
        expect(tester.takeException(), isNull);
        await support.signIn(repo, 'patient@example.test');
        final released = await repo.fetchPatientApprovedResults();
        expect(
          released,
          decision == ClinicalCaseStatus.approved ? hasLength(1) : isEmpty,
        );
      },
    );
  }
}
