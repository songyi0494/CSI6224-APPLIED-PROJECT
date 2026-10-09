import 'package:csi6224_patient_feedback/models/clinical_result_contract.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('terminal evaluation preserves actionable recommendation revisions', () {
    final evaluation = PathwayEvaluation.fromJson({
      'status': 'complete',
      'pathwayId': 'PATHWAY1',
      'pathwayRevision': 5,
      'investigationRevision': 2,
      'actions': [
        {
          'type': 'medication',
          'medication': 'Example treatment',
          'dose': 'Example dose',
        },
      ],
      'trace': <Object?>[],
    });

    expect(evaluation.canApprove, isTrue);
    expect(evaluation.pathwayRevision, 5);
    expect(evaluation.investigationRevision, 2);
    expect(
      evaluation.actions.single.description,
      contains('Example treatment'),
    );
  });

  test(
    'Common Advice maps only backend-provided recommendations and advice',
    () {
      final review = ClinicalResultsReview.fromJson({
        'vitaminD': {'recommendation': 'Vitamin D advice'},
        'calcium': {'recommendation': null},
        'protein': {'recommendation': 'Protein advice'},
        'lifestyleAdvice': ['Exercise advice'],
        'source': {
          'investigationRevision': 2,
          'questionnaireRevision': 3,
          'generatedAt': '2026-09-29T01:02:03Z',
        },
      });

      expect(review.commonAdvice, [
        'Vitamin D advice',
        'Exercise advice',
        'Protein advice',
      ]);
      expect(review.investigationRevision, 2);
      expect(review.questionnaireRevision, 3);
    },
  );

  test('case-scoped age projection does not require DOB in the payload', () {
    final summary = ClinicalCasePatientSummary.fromJson({
      'caseId': 'case-id',
      'patientDisplayName': 'Test Patient',
      'age': 71,
      'ageAsOf': '2026-09-29',
    });

    expect(summary.age, 71);
    expect(summary.ageAsOf, DateTime(2026, 9, 29));
  });

  test('patient result parser exposes only the approved safe payload', () {
    final result = PatientApprovedResult.fromJson({
      'caseId': 'case-id',
      'reviewedAt': '2026-09-29T01:02:03Z',
      'lifestyleRecommendations': ['Approved advice'],
      'careRecommendation': [
        {'type': 'recommendation', 'recommendation': 'Approved action'},
      ],
      'clinicianMessage': 'Approved message',
    });

    expect(result.lifestyleRecommendations, ['Approved advice']);
    expect(result.careRecommendations.single.description, 'Approved action');
    expect(result.clinicianMessage, 'Approved message');
  });
}
