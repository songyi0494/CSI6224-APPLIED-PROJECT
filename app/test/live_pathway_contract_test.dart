import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/live_pathway.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({MockAppRepository repository, String caseId})> clinicianCase() async {
  final repository = MockAppRepository();
  await repository.signIn(
    email: 'patient@example.test',
    password: 'DemoPass123!',
  );
  final assessment = (await repository.fetchClinicalCases()).single;
  await repository.submitAssessment(
    id: assessment.id,
    revision: assessment.revision,
    input: assessment.input,
  );
  await repository.signIn(
    email: 'clinician@example.test',
    password: 'DemoPass123!',
  );
  await repository.claimClinicalCase(assessment.id);
  await repository.saveCaseInvestigations(
    caseId: assessment.id,
    vitaminDLevel: 55,
    ionisedCalcium: 1.2,
    bodyWeightKg: 70,
    expectedRevision: 0,
  );
  return (repository: repository, caseId: assessment.id);
}

void main() {
  test('v12 response parser distinguishes question, complete and error', () {
    final question = LivePathwayResult.fromJson({
      'status': 'question',
      'pathwayId': 'PATHWAY1',
      'nodeId': 'RENAL_DYSFUNCTION',
      'question': 'Prompt',
      'requiredFacts': ['eGFR'],
      'trace': [],
    });
    final complete = LivePathwayResult.fromJson({
      'status': 'complete',
      'pathwayId': 'PATHWAY1',
      'actions': [],
      'trace': [],
    });
    final error = LivePathwayResult.fromJson({
      'status': 'error',
      'pathwayId': 'PATHWAY1',
      'error': 'Invalid rule graph',
      'trace': [],
    });
    expect(question, isA<PathwayQuestionStep>());
    expect(complete, isA<CompletedPathwayEvaluation>());
    expect(error, isA<PathwayRuntimeError>());
  });

  test('typed registry covers audited numeric and boolean facts', () {
    expect(pathwayFactRegistry['eGFR']!.kind, PathwayFactKind.number);
    expect(pathwayFactRegistry['hipTscore']!.allowNegative, isTrue);
    expect(
      pathwayFactRegistry['priorMIorStroke']!.kind,
      PathwayFactKind.boolean,
    );
    expect(pathwayFactRegistry, hasLength(25));
  });

  test('mock follows P1 and returns a multi-fact node', () async {
    final setup = await clinicianCase();
    expect(
      await setup.repository.evaluatePathway(caseId: setup.caseId),
      isA<PathwayQuestionStep>(),
    );
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: 'eGFR',
      value: 54.0,
    );
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: 'osteoporosisTreatmentStatus',
      value: false,
    );
    final result =
        await setup.repository.evaluatePathway(caseId: setup.caseId)
            as PathwayQuestionStep;
    expect(result.nodeId, 'RESIDENTIAL_OR_FRAILTY');
    expect(result.requiredFacts, [
      'liveInResidentialCare',
      'clinicalFrailtyScore',
      'lifeExpectancy',
    ]);
  });

  test('P1 redirects to P2 without manual routing', () async {
    final setup = await clinicianCase();
    await setup.repository.evaluatePathway(caseId: setup.caseId);
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: 'eGFR',
      value: 54,
    );
    await setup.repository.savePathwayAnswer(
      caseId: setup.caseId,
      fieldKey: 'osteoporosisTreatmentStatus',
      value: true,
    );
    final result =
        await setup.repository.evaluatePathway(caseId: setup.caseId)
            as PathwayQuestionStep;
    expect(result.pathwayId, 'PATHWAY2');
    expect(result.requiredFacts, ['antiresorptiveTreatmentStatus']);
  });

  test(
    'previous answer edit re-evaluates and completion locks facts',
    () async {
      final setup = await clinicianCase();
      await setup.repository.evaluatePathway(caseId: setup.caseId);
      await setup.repository.savePathwayAnswer(
        caseId: setup.caseId,
        fieldKey: 'eGFR',
        value: 54,
      );
      expect(
        await setup.repository.evaluatePathway(caseId: setup.caseId),
        isA<PathwayQuestionStep>(),
      );
      await setup.repository.savePathwayAnswer(
        caseId: setup.caseId,
        fieldKey: 'eGFR',
        value: 20,
      );
      expect(
        await setup.repository.evaluatePathway(caseId: setup.caseId),
        isA<CompletedPathwayEvaluation>(),
      );
      expect(
        () => setup.repository.savePathwayAnswer(
          caseId: setup.caseId,
          fieldKey: 'eGFR',
          value: 30,
        ),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('answer persistence rejects string JSON values', () async {
    final setup = await clinicianCase();
    await setup.repository.evaluatePathway(caseId: setup.caseId);
    expect(
      () => setup.repository.savePathwayAnswer(
        caseId: setup.caseId,
        fieldKey: 'eGFR',
        value: '54',
      ),
      throwsA(isA<AppException>()),
    );
  });
}
