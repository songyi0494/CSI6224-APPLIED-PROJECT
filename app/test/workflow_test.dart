import 'dart:convert';
import 'dart:io';
import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/mock_app_repository.dart';
import 'package:csi6224_patient_feedback/models/app_user.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
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
      final review = await repo.fetchClinicalCase(a.id);
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
}
