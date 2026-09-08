import 'package:csi6224_patient_feedback/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on role-based sign-in screen', (tester) async {
    await tester.pumpWidget(const OsteoporosisPathwaysApp());

    expect(find.text('Osteoporosis Pathways'), findsOneWidget);
    expect(find.text('Clinician'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
  });

  testWidgets('clinician Manage opens the questionnaire builder',
      (tester) async {
    await _signInAsClinician(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Questionnaire builder'), findsOneWidget);
    expect(find.text('Create questionnaire'), findsOneWidget);
  });

  testWidgets('clinician can open the Avery Martin pathway draft',
      (tester) async {
    await _signInAsClinician(tester);

    await tester.ensureVisible(find.byTooltip('Open case'));
    await tester.tap(find.byTooltip('Open case'));
    await tester.pumpAndSettle();

    expect(find.text('Pathway clinical input'), findsOneWidget);
    expect(_textFieldAt(tester, 0).controller?.text, 'Avery Martin');
    expect(_textFieldAt(tester, 1).controller?.text, '74');
  });

  testWidgets('clinician can open a blank new pathway case', (tester) async {
    await _signInAsClinician(tester);

    await tester
        .tap(find.widgetWithText(FloatingActionButton, 'New pathway case'));
    await tester.pumpAndSettle();

    expect(find.text('Pathway clinical input'), findsOneWidget);
    expect(_textFieldAt(tester, 0).controller?.text, isEmpty);
  });

  testWidgets('saving a new pathway draft returns and refreshes the dashboard',
      (tester) async {
    await _signInAsClinician(tester);

    await tester
        .tap(find.widgetWithText(FloatingActionButton, 'New pathway case'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Jordan Lee');
    await _scrollUntilTextIsBuilt(tester, 'Save draft');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save draft'));
    await tester.pumpAndSettle();

    expect(find.text('Clinician workspace'), findsOneWidget);
    expect(find.text('Jordan Lee'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
  });
}

Future<void> _signInAsClinician(WidgetTester tester) async {
  await tester.pumpWidget(const OsteoporosisPathwaysApp());
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();

  expect(find.text('Clinician workspace'), findsOneWidget);
}

TextField _textFieldAt(WidgetTester tester, int index) {
  return tester.widgetList<TextField>(find.byType(TextField)).elementAt(index);
}

Future<void> _scrollUntilTextIsBuilt(
  WidgetTester tester,
  String text,
) async {
  for (var i = 0; i < 8 && find.text(text).evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  expect(find.text(text), findsOneWidget);
}
