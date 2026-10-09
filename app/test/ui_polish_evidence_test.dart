import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csi6224_patient_feedback/screens/patient_home_screen.dart';
import 'package:csi6224_patient_feedback/screens/patient_recommendation_screen.dart';
import 'package:csi6224_patient_feedback/screens/pathway_question_screen.dart';
import 'package:csi6224_patient_feedback/screens/recommendation_review_screen.dart';
import 'ui_polish_support.dart';
import '../../evidence/final-ui-polish-20261009/before_patient_home.dart'
    as baseline;
import '../../evidence/final-ui-polish-20261009/before_patient_recommendation.dart'
    as baseline_care;

void main() {
  for (final scene in [
    'patient-dashboard',
    'patient-care-plan',
    'minimal-trauma',
    'fracture-site',
    'adherence',
    'why-recommendation',
    'technical-trace',
    'saved-decision',
  ]) {
    testWidgets(
      'synthetic screenshot $scene',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final font = FontLoader('EvidenceFont')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytesSync(),
              ),
            ),
          );
        await tester.runAsync(() => font.load());
        final symbols = FontLoader('EvidenceSymbols')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(r'C:\Windows\Fonts\seguisym.ttf').readAsBytesSync(),
              ),
            ),
          );
        await tester.runAsync(() => symbols.load());
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  r'C:\dev\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await tester.runAsync(() => icons.load());
        final node = switch (scene) {
          'minimal-trauma' => 'MINIMAL_TRAUMA_FRACTURE',
          'fracture-site' => 'FRACTURE_SITE_ELIGIBLE',
          'adherence' => 'ADHERENCE_CONCERN',
          _ => null,
        };
        final repo = PolishRepository(
          node: node,
          approved: scene != 'saved-decision',
          fixture: scene == 'patient-care-plan' ? 'p2' : 'p1',
        );
        final Widget screen = scene == 'patient-dashboard'
            ? Platform.environment['SONGYI_UI_EVIDENCE_PHASE'] == 'before'
                  ? baseline.PatientHomeScreen(
                      user: patient,
                      repository: repo,
                      onSignOut: () {},
                    )
                  : PatientHomeScreen(
                      user: patient,
                      repository: repo,
                      onSignOut: () {},
                    )
            : scene == 'patient-care-plan'
            ? Platform.environment['SONGYI_UI_EVIDENCE_PHASE'] == 'before'
                  ? baseline_care.PatientRecommendationScreen(
                      result: await repo.result(),
                    )
                  : PatientRecommendationScreen(
                      result: await repo.result(),
                      onSignOut: () {},
                    )
            : node != null
            ? PathwayQuestionScreen(caseId: 'evidence-case', repository: repo)
            : RecommendationReviewScreen(
                caseId: 'evidence-case',
                repository: repo,
              );
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'EvidenceFont',
                fontFamilyFallback: const ['EvidenceSymbols'],
                colorSchemeSeed: Colors.teal,
              ),
              home: screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene == 'saved-decision') {
          await tester.ensureVisible(find.text('Approve'));
          await tester.tap(find.text('Approve'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).last,
            'Please discuss these options with your GP.',
          );
          await tester.ensureVisible(find.text('Save decision'));
          await tester.tap(find.text('Save decision'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Decision status'));
          await tester.pumpAndSettle();
        }
        if (scene == 'technical-trace') {
          await tester.ensureVisible(find.text('View technical trace'));
          await tester.tap(find.text('View technical trace'));
          await tester.pumpAndSettle();
        }
        if (scene == 'why-recommendation') {
          await tester.ensureVisible(find.text('Why this recommendation'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final dir = Platform.environment['SONGYI_UI_EVIDENCE_DIR'];
        if (dir != null) {
          final phase =
              Platform.environment['SONGYI_UI_EVIDENCE_PHASE'] ?? 'after';
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = (await tester.runAsync(
            () => boundary.toImage(pixelRatio: 1),
          ))!;
          final png = await tester.runAsync(
            () => img.toByteData(format: ui.ImageByteFormat.png),
          );
          await tester.runAsync(() async {
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/$phase-$scene.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
          img.dispose();
        }
      },
      skip:
          Platform.environment['SONGYI_UI_EVIDENCE_PHASE'] == 'before' &&
          !scene.startsWith('patient-'),
    );
  }
}
