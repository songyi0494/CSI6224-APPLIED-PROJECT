import 'package:csi6224_patient_feedback/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on role-based sign-in screen', (tester) async {
    await tester.pumpWidget(const OsteoporosisPathwaysApp());

    expect(find.text('Osteoporosis Pathways'), findsOneWidget);
    expect(find.text('Clinician'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
  });
}
