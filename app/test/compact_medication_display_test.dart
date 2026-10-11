import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/widgets/pathway_action_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final alternatives = PathwayAction.fromJson({
  'type': 'treatmentOptions',
  'options': [
    {
      'type': 'medication',
      'medication': 'Example A',
      'dose': '5 mg',
      'route': 'Oral',
      'frequency': 'Weekly',
      'duration': '3 years',
      'warnings': [
        'Recorded safety warning. Do not combine these alternatives.',
      ],
    },
    {
      'type': 'medication',
      'medication': 'Example B',
      'dose': '60 mg',
      'route': 'Subcutaneous',
      'frequency': 'Every 6 months',
    },
  ],
});

Future<void> mount(WidgetTester tester, PathwayAction action, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: PathwayActionView(action: action, compactMedications: true),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop alternatives share a compact five-column row', (
    tester,
  ) async {
    await mount(tester, alternatives, const Size(1000, 800));
    expect(find.text('Medication alternatives'), findsOneWidget);
    expect(
      find.text(
        'Alternatives for clinician review. These are not simultaneous prescriptions.',
      ),
      findsOneWidget,
    );
    final rowY = tester.getTopLeft(find.text('Example A')).dy;
    for (final value in ['5 mg', 'Oral', 'Weekly', '3 years']) {
      expect(tester.getTopLeft(find.text(value)).dy, closeTo(rowY, 1));
    }
    expect(tester.getTopLeft(find.text('Example B')).dy, greaterThan(rowY));
    expect(find.textContaining('Recorded safety warning.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow rows wrap long doses and all safety details without overflow',
    (tester) async {
      final action = PathwayAction.fromJson({
        'type': 'treatmentOptions',
        'options': [
          {
            'type': 'medication',
            'medication': 'Long example medication name',
            'dose':
                'Full recorded dose instructions that must remain visible without ellipsis',
            'route': 'Subcutaneous',
            'frequency': 'Every 6 months',
            'duration': '18–24 months',
            'instructions':
                'Full recorded safety instructions and follow-up details.',
          },
        ],
      });
      await mount(tester, action, const Size(320, 800));
      expect(
        find.text(
          'Dose: Full recorded dose instructions that must remain visible without ellipsis',
        ),
        findsOneWidget,
      );
      expect(find.text('Duration: 18–24 months'), findsOneWidget);
      expect(
        find.textContaining(
          'Full recorded safety instructions and follow-up details.',
        ),
        findsOneWidget,
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact medications retain separate care plans and other actions',
    (tester) async {
      final action = PathwayAction.fromJson({
        'type': 'actionOptions',
        'options': [
          [
            alternatives.raw,
            {'type': 'followUp', 'destination': 'GP', 'when': 'In 4 weeks'},
            {'type': 'instruction', 'instruction': 'Recorded safety advice.'},
          ],
          [
            {
              'type': 'referral',
              'destination': 'SPECIALIST',
              'reason': 'Recorded referral reason',
            },
          ],
        ],
      });
      await mount(tester, action, const Size(1000, 800));
      expect(find.text('Care plan 1'), findsOneWidget);
      expect(find.text('Care plan 2'), findsOneWidget);
      expect(find.text('Follow up with GP\nWhen: In 4 weeks'), findsOneWidget);
      expect(
        find.text('Refer to Specialist: Recorded referral reason'),
        findsOneWidget,
      );
      expect(find.text('Recorded safety advice.'), findsOneWidget);
      expect(find.textContaining('Recorded safety warning.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
