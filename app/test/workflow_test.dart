import 'dart:convert';
import 'dart:io';
import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/clinical_input.dart';
import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/clinical_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockAppRepository repo;
  setUp(
    () => repo = MockAppRepository(
      evaluate: (input) async => PathwayEvaluation.fromJson(
        jsonDecode(
              File(
                'test/fixtures/${input.treated == true ? 'pathway2' : 'pathway1'}_result.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      ),
    ),
  );
  Future<void> login(String email) async {
    await repo.signIn(email: email, password: 'DemoPass123!');
  }

  const completeClinicianInput = Pathway1ClinicianInput(
    egfr: 54,
    clinicalFrailtyScore: 4,
    lifeExpectancy: 10,
    knownPoorMedicationAdherence: false,
    cognitiveImpairment: false,
    dxaDoneWithinPrevious2Years: true,
    dxaImpractical: false,
    tScoreValue: -3.5,
    tScoreSite: 'hip',
    hipVertebralOrMultipleFracturesInLast24M: true,
    yearsSinceMenopause: 20,
  );

  test(
    'mock uses treatment data, keeps patient identity and hides unapproved results',
    () async {
      await login('patient@example.test');
      final a = (await repo.fetchClinicalCases()).single;
      final submitted = await repo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: a.input,
      );
      expect(submitted.pathway, ClinicalPathway.pathway1);
      expect(submitted.status, ClinicalCaseStatus.clinicianInputRequired);
      expect(submitted.patientId, 'patient-a');
      expect(submitted.evaluation, isNull);
      expect(submitted.approvedActions, isEmpty);
      await login('treated@example.test');
      expect(() => repo.fetchClinicalCase(a.id), throwsA(isA<AppException>()));
      final b = (await repo.fetchClinicalCases()).single;
      final treated = await repo.submitAssessment(
        id: b.id,
        revision: b.revision,
        input: b.input,
      );
      expect(treated.pathway, ClinicalPathway.pathway2);
      expect(treated.status, ClinicalCaseStatus.manualReview);
    },
  );
  test(
    'clinician decision is retained in mock session and stale decisions fail',
    () async {
      await login('patient@example.test');
      final a = (await repo.fetchClinicalCases()).single;
      await repo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: a.input,
      );
      await login('clinician@example.test');
      final clinicalInput = await repo.fetchClinicalCase(a.id);
      final review = await repo.completePathway1ClinicianInput(
        assessment: clinicalInput,
        input: completeClinicianInput,
      );
      await repo.recordClinicianDecision(
        assessment: review,
        decision: ClinicalCaseStatus.approved,
        notes: 'Reviewed.',
      );
      expect(
        () => repo.recordClinicianDecision(
          assessment: review,
          decision: ClinicalCaseStatus.withheld,
          notes: 'Stale.',
        ),
        throwsA(isA<AppException>()),
      );
      await login('patient@example.test');
      final result = await repo.fetchClinicalCase(a.id);
      expect(result.status, ClinicalCaseStatus.approved);
      expect(result.approvedActions, isNotEmpty);
      expect(result.evaluation, isNull);
    },
  );
  test(
    'clinician registration begins pending and public admin registration fails',
    () async {
      await repo.signUp(
        const RegistrationInput(
          name: 'New clinician',
          email: 'new@example.test',
          password: 'DemoPass123!',
          role: UserRole.clinician,
        ),
      );
      await login('new@example.test');
      expect(
        (await repo.loadProfile())!.approvalStatus,
        ClinicianApprovalStatus.pending,
      );
      expect(await repo.fetchClinicalCases(), isEmpty);
      expect(
        () => repo.reviewClinician(
          'clinician-b',
          ClinicianApprovalStatus.approved,
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        () => repo.signUp(
          const RegistrationInput(
            name: 'Admin',
            email: 'bad@example.test',
            password: 'DemoPass123!',
            role: UserRole.admin,
          ),
        ),
        throwsA(isA<AppException>()),
      );
    },
  );
  test(
    'patient-submitted highRisk is ignored and remains clinician-confirmed',
    () async {
      final localRepo = MockAppRepository();
      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final a = (await localRepo.fetchClinicalCases()).single;
      final facts = Map<String, dynamic>.from(a.input.toFacts());
      facts.addAll({
        'T-score': -3.5,
        'hipVertebralOrMultipleFracturesInLast24M': false,
        'highRisk': true,
      });

      final submitted = await localRepo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: ClinicalInput.fromFacts(facts),
      );
      expect(submitted.status, ClinicalCaseStatus.clinicianInputRequired);
      expect(submitted.evaluation, isNull);

      await localRepo.signIn(
        email: 'clinician@example.test',
        password: 'DemoPass123!',
      );
      final review = await localRepo.completePathway1ClinicianInput(
        assessment: await localRepo.fetchClinicalCase(a.id),
        input: const Pathway1ClinicianInput(
          egfr: 54,
          clinicalFrailtyScore: 4,
          lifeExpectancy: 10,
          knownPoorMedicationAdherence: false,
          cognitiveImpairment: false,
          dxaDoneWithinPrevious2Years: true,
          dxaImpractical: false,
          tScoreValue: -3.5,
          tScoreSite: 'hip',
          hipVertebralOrMultipleFracturesInLast24M: false,
          yearsSinceMenopause: 20,
        ),
      );
      expect(review.status, ClinicalCaseStatus.clinicianInputRequired);
      expect(review.evaluation!.decision, 'needs_more_information');
      expect(review.evaluation!.missingInputs, contains('highRisk'));
      expect(
        review.evaluation!.trace.last.ruleId,
        'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE',
      );
      expect(review.evaluation!.trace.last.matched, isNull);
      expect(
        review.evaluation!.trace.last.reason,
        contains('clinician confirmation'),
      );
    },
  );
  test(
    'postmenopausal true survives patient submit and clinician evaluation',
    () async {
      final localRepo = MockAppRepository();
      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final a = (await localRepo.fetchClinicalCases()).single;
      final facts = Map<String, dynamic>.from(a.input.toFacts())
        ..['postmenopausal'] = true;

      final submitted = await localRepo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: ClinicalInput.fromFacts(facts),
      );
      expect(submitted.input.postmenopausal, isTrue);

      await localRepo.signIn(
        email: 'clinician@example.test',
        password: 'DemoPass123!',
      );
      final clinicianCase = await localRepo.fetchClinicalCase(a.id);
      expect(clinicianCase.input.postmenopausal, isTrue);
      expect(factText(clinicianCase.input.toFacts()['postmenopausal']), 'Yes');

      final review = await localRepo.completePathway1ClinicianInput(
        assessment: clinicianCase,
        input: completeClinicianInput,
      );
      expect(
        review.evaluation!.missingInputs,
        isNot(contains('postmenopausal')),
      );
    },
  );
  test('postmenopausal false survives patient submit unchanged', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    final facts = Map<String, dynamic>.from(a.input.toFacts())
      ..['postmenopausal'] = false;

    final submitted = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: ClinicalInput.fromFacts(facts),
    );
    expect(submitted.input.postmenopausal, isFalse);

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    final clinicianCase = await localRepo.fetchClinicalCase(a.id);
    expect(clinicianCase.input.postmenopausal, isFalse);
    expect(factText(clinicianCase.input.toFacts()['postmenopausal']), 'No');
  });
  test(
    'postmenopausal unknown remains unknown and evaluator can request it',
    () async {
      final localRepo = MockAppRepository();
      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final a = (await localRepo.fetchClinicalCases()).single;
      final facts = Map<String, dynamic>.from(a.input.toFacts())
        ..remove('postmenopausal');

      final submitted = await localRepo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: ClinicalInput.fromFacts(facts),
      );
      expect(submitted.input.postmenopausal, isNull);

      await localRepo.signIn(
        email: 'clinician@example.test',
        password: 'DemoPass123!',
      );
      final clinicianCase = await localRepo.fetchClinicalCase(a.id);
      expect(clinicianCase.input.postmenopausal, isNull);
      expect(
        factText(clinicianCase.input.toFacts()['postmenopausal']),
        'Not provided',
      );

      final review = await localRepo.completePathway1ClinicianInput(
        assessment: clinicianCase,
        input: completeClinicianInput,
      );
      expect(review.evaluation!.missingInputs, contains('postmenopausal'));
    },
  );
  test(
    'mock derives age from patient DOB and ignores caller-supplied age',
    () async {
      final localRepo = MockAppRepository();
      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final a = (await localRepo.fetchClinicalCases()).single;
      final dobDerivedAge = a.input.age;
      final facts = Map<String, dynamic>.from(a.input.toFacts())..['age'] = 12;

      final submitted = await localRepo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: ClinicalInput.fromFacts(facts),
      );

      expect(submitted.input.age, dobDerivedAge);
      expect(submitted.input.age, isNot(12));
    },
  );
  test('draft assessment blocks creating a second active assessment', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;

    expect(a.status, ClinicalCaseStatus.draft);
    expect(
      () => localRepo.saveAssessment(
        id: 'second-active-draft',
        revision: 0,
        input: a.input,
      ),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'submitted and review states block duplicate active assessments',
    () async {
      for (final state in [
        ClinicalCaseStatus.clinicianInputRequired,
        ClinicalCaseStatus.awaitingReview,
        ClinicalCaseStatus.needsMoreInfo,
      ]) {
        final localRepo = MockAppRepository();
        await localRepo.signIn(
          email: 'patient@example.test',
          password: 'DemoPass123!',
        );
        final a = (await localRepo.fetchClinicalCases()).single;
        await localRepo.submitAssessment(
          id: a.id,
          revision: a.revision,
          input: a.input,
        );
        if (state != ClinicalCaseStatus.clinicianInputRequired) {
          await localRepo.signIn(
            email: 'clinician@example.test',
            password: 'DemoPass123!',
          );
          final review = await localRepo.completePathway1ClinicianInput(
            assessment: await localRepo.fetchClinicalCase(a.id),
            input: completeClinicianInput,
          );
          if (state == ClinicalCaseStatus.needsMoreInfo) {
            await localRepo.recordClinicianDecision(
              assessment: review,
              decision: ClinicalCaseStatus.needsMoreInfo,
              notes: 'Please confirm additional information.',
            );
          }
          await localRepo.signIn(
            email: 'patient@example.test',
            password: 'DemoPass123!',
          );
        }

        final current = (await localRepo.fetchClinicalCases()).single;
        expect(current.status, state);
        expect(
          () => localRepo.saveAssessment(
            id: 'second-active-${state.value}',
            revision: 0,
            input: current.input,
          ),
          throwsA(isA<AppException>()),
        );
      }
    },
  );
  test('needs more information does not reopen direct patient editing', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );
    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    final review = await localRepo.completePathway1ClinicianInput(
      assessment: await localRepo.fetchClinicalCase(a.id),
      input: completeClinicianInput,
    );
    await localRepo.recordClinicianDecision(
      assessment: review,
      decision: ClinicalCaseStatus.needsMoreInfo,
      notes: 'Please confirm additional information.',
    );

    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final current = (await localRepo.fetchClinicalCases()).single;
    expect(current.status, ClinicalCaseStatus.needsMoreInfo);
    expect(current.canEdit, isFalse);
    expect(
      () => localRepo.saveAssessment(
        id: current.id,
        revision: current.revision,
        input: current.input,
      ),
      throwsA(isA<AppException>()),
    );
  });
  test('manual review blocks duplicate active assessments', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'treated@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    final manualReview = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    expect(manualReview.status, ClinicalCaseStatus.manualReview);
    expect(
      () => localRepo.saveAssessment(
        id: 'second-active-manual-review',
        revision: 0,
        input: manualReview.input,
      ),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'approved historical assessment allows a new active assessment',
    () async {
      final localRepo = MockAppRepository();
      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final a = (await localRepo.fetchClinicalCases()).single;
      await localRepo.submitAssessment(
        id: a.id,
        revision: a.revision,
        input: a.input,
      );
      await localRepo.signIn(
        email: 'clinician@example.test',
        password: 'DemoPass123!',
      );
      final review = await localRepo.completePathway1ClinicianInput(
        assessment: await localRepo.fetchClinicalCase(a.id),
        input: completeClinicianInput,
      );
      await localRepo.recordClinicianDecision(
        assessment: review,
        decision: ClinicalCaseStatus.approved,
        notes: 'Reviewed recommendation and clinical inputs.',
      );

      await localRepo.signIn(
        email: 'patient@example.test',
        password: 'DemoPass123!',
      );
      final newAssessment = await localRepo.saveAssessment(
        id: 'new-after-approved',
        revision: 0,
        input: a.input,
      );
      final assessments = await localRepo.fetchClinicalCases();
      expect(newAssessment.status, ClinicalCaseStatus.draft);
      expect(assessments, hasLength(2));
      expect(
        assessments.where(
          (assessment) => assessment.status == ClinicalCaseStatus.approved,
        ),
        hasLength(1),
      );
    },
  );
  test('repeat submit of the same assessment revision is idempotent', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;

    final first = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );
    final second = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    expect(second.id, first.id);
    expect(second.revision, first.revision);
    expect(await localRepo.fetchClinicalCases(), hasLength(1));
  });
  test('patient can withdraw submitted assessment before clinician input', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    final submitted = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    expect(await localRepo.fetchClinicalCases(), hasLength(1));

    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final withdrawn = await localRepo.withdrawAssessment(assessment: submitted);
    expect(withdrawn.id, submitted.id);
    expect(withdrawn.revision, submitted.revision);
    expect(withdrawn.status, ClinicalCaseStatus.draft);
    expect(withdrawn.input.toFacts(), submitted.input.toFacts());

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    expect(await localRepo.fetchClinicalCases(), isEmpty);

    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final facts = Map<String, dynamic>.from(withdrawn.input.toFacts())
      ..['fractureSite'] = 'hip';
    final resubmitted = await localRepo.submitAssessment(
      id: withdrawn.id,
      revision: withdrawn.revision,
      input: ClinicalInput.fromFacts(facts),
    );
    expect(resubmitted.id, submitted.id);
    expect(resubmitted.status, ClinicalCaseStatus.clinicianInputRequired);
    expect(resubmitted.input.fractureSite, 'hip');
    expect(resubmitted.revision, withdrawn.revision + 1);
    expect(
      () => localRepo.saveAssessment(
        id: 'second-active-after-withdraw',
        revision: 0,
        input: resubmitted.input,
      ),
      throwsA(isA<AppException>()),
    );

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    expect(await localRepo.fetchClinicalCases(), hasLength(1));
  });
  test('withdrawal is blocked after clinician processing starts', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    final submitted = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    final review = await localRepo.completePathway1ClinicianInput(
      assessment: await localRepo.fetchClinicalCase(a.id),
      input: completeClinicianInput,
    );

    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    expect(
      () => localRepo.withdrawAssessment(assessment: submitted),
      throwsA(isA<AppException>()),
    );

    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    await localRepo.recordClinicianDecision(
      assessment: review,
      decision: ClinicalCaseStatus.approved,
      notes: 'Reviewed recommendation and clinical inputs.',
    );
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final approved = (await localRepo.fetchClinicalCases()).single;
    expect(
      () => localRepo.withdrawAssessment(assessment: approved),
      throwsA(isA<AppException>()),
    );
  });
  test('withdrawal requires owner and current version token', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    final submitted = await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );

    await localRepo.signIn(
      email: 'treated@example.test',
      password: 'DemoPass123!',
    );
    expect(
      () => localRepo.withdrawAssessment(assessment: submitted),
      throwsA(isA<AppException>()),
    );

    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    await localRepo.withdrawAssessment(assessment: submitted);
    expect(
      () => localRepo.withdrawAssessment(assessment: submitted),
      throwsA(isA<AppException>()),
    );
  });
  test('clinician highRisk choices keep unknown distinct from false', () async {
    final localRepo = MockAppRepository();
    await localRepo.signIn(
      email: 'patient@example.test',
      password: 'DemoPass123!',
    );
    final a = (await localRepo.fetchClinicalCases()).single;
    await localRepo.submitAssessment(
      id: a.id,
      revision: a.revision,
      input: a.input,
    );
    await localRepo.signIn(
      email: 'clinician@example.test',
      password: 'DemoPass123!',
    );
    final needsHighRisk = await localRepo.completePathway1ClinicianInput(
      assessment: await localRepo.fetchClinicalCase(a.id),
      input: const Pathway1ClinicianInput(
        egfr: 54,
        clinicalFrailtyScore: 4,
        lifeExpectancy: 10,
        knownPoorMedicationAdherence: false,
        cognitiveImpairment: false,
        dxaDoneWithinPrevious2Years: true,
        dxaImpractical: false,
        tScoreValue: -3.5,
        tScoreSite: 'hip',
        hipVertebralOrMultipleFracturesInLast24M: false,
        yearsSinceMenopause: 20,
      ),
    );
    expect(needsHighRisk.status, ClinicalCaseStatus.clinicianInputRequired);

    final specialist = await localRepo.completePathway1ClinicianInput(
      assessment: needsHighRisk,
      input: const Pathway1ClinicianInput(
        egfr: 54,
        clinicalFrailtyScore: 4,
        lifeExpectancy: 10,
        knownPoorMedicationAdherence: false,
        cognitiveImpairment: false,
        dxaDoneWithinPrevious2Years: true,
        dxaImpractical: false,
        tScoreValue: -3.5,
        tScoreSite: 'hip',
        hipVertebralOrMultipleFracturesInLast24M: false,
        clinicianConfirmedVeryHighRisk: true,
        yearsSinceMenopause: 20,
      ),
    );
    expect(specialist.status, ClinicalCaseStatus.awaitingReview);
    expect(
      specialist.evaluation!.trace.last.ruleId,
      'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE',
    );
    expect(specialist.evaluation!.trace.last.matched, isTrue);
  });
}
