import 'dart:convert';

import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('zero visible clinical cases returns an empty list', () async {
    late http.Request clinicalCaseRequest;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      httpClient: MockClient((request) async {
        clinicalCaseRequest = request;
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final cases = await SupabaseAppRepository(client).fetchClinicalCases();

    expect(cases, isEmpty);
    expect(
      clinicalCaseRequest.url.queryParameters['select'],
      SupabaseAppRepository.clinicalCaseListSelectColumns.replaceAll(' ', ''),
    );
    expect(
      clinicalCaseRequest.url.queryParameters,
      isNot(contains('patient_id')),
    );
    expect(
      clinicalCaseRequest.url.queryParameters['order'],
      'updated_at.desc.nullslast',
    );
  });

  test(
    'live case parses when nullable fields and profile enrichment are unavailable',
    () async {
      var profileLookupAttempted = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/clinical_cases')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'case-id',
                  'patient_id': 'patient-id',
                  'status': 'clinician_input_required',
                  'submitted_at': '2026-09-26T01:02:03Z',
                  'updated_at': '2026-09-26T01:02:03Z',
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/profiles')) {
            profileLookupAttempted = true;
            return http.Response(
              jsonEncode({
                'message': 'profile name is not visible',
                'code': '42501',
                'details': null,
                'hint': null,
              }),
              403,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not found', 404, request: request);
        }),
      );
      addTearDown(client.dispose);

      final cases = await SupabaseAppRepository(client).fetchClinicalCases();

      expect(profileLookupAttempted, isTrue);
      expect(cases, hasLength(1));
      final clinicalCase = cases.single;
      expect(clinicalCase.id, 'case-id');
      expect(clinicalCase.patientId, 'patient-id');
      expect(clinicalCase.patientName, 'Patient');
      expect(clinicalCase.assignedClinicianId, isNull);
      expect(clinicalCase.pathway, isNull);
      expect(clinicalCase.routingReason, isNull);
      expect(clinicalCase.revision, 0);
      expect(clinicalCase.questionnaireResponseId, isNull);
      expect(clinicalCase.clinicianFacts, isEmpty);
      expect(clinicalCase.evaluation, isNull);
    },
  );

  test(
    'single case uses the bounded clinician detail select contract',
    () async {
      late http.Request clinicalCaseRequest;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/get_clinical_case_detail')) {
            clinicalCaseRequest = request;
            return http.Response(
              jsonEncode({
                'id': 'case-id',
                'patient_id': 'patient-id',
                'patient_name': 'Profile Patient',
                'profile_sex_at_birth': 'female',
                'clinician_facts': <String, Object?>{'eGFR': 55},
                'pathway': 'PATHWAY1',
                'routing_reason': 'test',
                'status': 'evaluated',
                'pathway_revision': 5,
                'questionnaire_response_id': 'response-id',
                'rule_evaluation': {
                  'status': 'complete',
                  'pathwayId': 'PATHWAY1',
                  'pathwayRevision': 5,
                  'investigationRevision': 2,
                  'actions': [
                    {'type': 'medication', 'medication': 'Example treatment'},
                  ],
                  'trace': <Object?>[],
                },
                'submitted_at': '2026-09-26T01:02:03Z',
                'updated_at': '2026-09-26T01:02:03Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response('Not found', 404, request: request);
        }),
      );
      addTearDown(client.dispose);

      final clinicalCase = await SupabaseAppRepository(
        client,
      ).fetchClinicalCase('case-id');

      expect(
        clinicalCaseRequest.url.path,
        endsWith('/rpc/${SupabaseAppRepository.clinicalCaseDetailRpc}'),
      );
      expect(jsonDecode(clinicalCaseRequest.body), {'p_case_id': 'case-id'});
      expect(clinicalCase.patientName, 'Profile Patient');
      expect(clinicalCase.patientSexAtBirth, 'female');
      expect(clinicalCase.clinicianFacts, {'eGFR': 55});
      expect(clinicalCase.pathway, ClinicalPathway.pathway1);
      expect(clinicalCase.routingReason, 'test');
      expect(clinicalCase.pathwayRevision, 5);
      expect(clinicalCase.questionnaireResponseId, 'response-id');
      expect(clinicalCase.evaluation?.actions, hasLength(1));
      expect(clinicalCase.evaluation?.canApprove, isTrue);
    },
  );

  test(
    'case-detail failure logs bounded diagnostics and keeps safe UI error',
    () async {
      final originalDebugPrint = debugPrint;
      final diagnostics = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) diagnostics.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'message':
                  'permission denied for table clinical_cases for 40000000-0000-4000-8000-000000000001 test@example.com',
              'code': '42501',
              'details': null,
              'hint': null,
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        SupabaseAppRepository(
          client,
        ).fetchClinicalCase('40000000-0000-4000-8000-000000000001'),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            'We could not load this assessment. Please try again.',
          ),
        ),
      );

      final output = diagnostics.join('\n');
      expect(output, contains('CLINICAL CASE DETAIL LOAD ERROR:'));
      expect(output, contains('type=PostgrestException'));
      expect(output, contains('code=42501'));
      expect(output, contains('permission denied for table clinical_cases'));
      expect(output, contains('<redacted-uuid>'));
      expect(output, contains('<redacted-email>'));
      expect(output, isNot(contains('40000000-0000-4000-8000-000000000001')));
      expect(output, isNot(contains('test@example.com')));
    },
  );

  test('age and Common Advice use bounded case-scoped RPCs', () async {
    final paths = <String>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/get_clinical_case_patient_summary')) {
          return http.Response(
            jsonEncode({
              'caseId': 'case-id',
              'patientDisplayName': 'Test Patient',
              'age': 71,
              'ageAsOf': '2026-09-29',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith('/get_clinical_case_results_review')) {
          return http.Response(
            jsonEncode({
              'vitaminD': {'recommendation': 'Vitamin D advice'},
              'calcium': {'recommendation': null},
              'protein': {'recommendation': 'Protein advice'},
              'lifestyleAdvice': ['Exercise advice'],
              'source': {
                'investigationRevision': 2,
                'questionnaireRevision': 3,
                'generatedAt': '2026-09-29T01:02:03Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('Not found', 404, request: request);
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseAppRepository(client);

    final summary = await repository.getClinicalCasePatientSummary('case-id');
    final review = await repository.getClinicalCaseResultsReview('case-id');

    expect(summary.age, 71);
    expect(review?.commonAdvice, [
      'Vitamin D advice',
      'Exercise advice',
      'Protein advice',
    ]);
    expect(paths, contains(endsWith('/get_clinical_case_patient_summary')));
    expect(paths, contains(endsWith('/get_clinical_case_results_review')));
  });

  test(
    'missing approved-result projection fails closed to an empty list',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'message':
                  'Could not find the function public.get_patient_approved_results in the schema cache',
              'code': 'PGRST202',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);

      expect(
        await SupabaseAppRepository(client).fetchPatientApprovedResults(),
        isEmpty,
      );
    },
  );

  test(
    'live withdrawal fails closed without calling an unverified RPC',
    () async {
      var requestCount = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-test-key',
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response('Unexpected request', 500, request: request);
        }),
      );
      addTearDown(client.dispose);
      final waitingCase = ClinicalCase.fromJson({
        'id': 'case-id',
        'patient_id': 'patient-id',
        'facts': <String, Object?>{},
        'status': 'clinician_input_required',
        'revision': 0,
        'updated_at': '2026-09-28T01:02:03Z',
      });

      await expectLater(
        SupabaseAppRepository(
          client,
        ).withdrawAssessment(assessment: waitingCase),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            contains('Withdrawal is not available'),
          ),
        ),
      );
      expect(requestCount, 0);
    },
  );

  test(
    'verified live case statuses expose distinct patient wording and locks',
    () {
      ClinicalCase caseWithStatus(String status) => ClinicalCase.fromJson({
        'id': 'case-$status',
        'patient_id': 'patient-id',
        'facts': <String, Object?>{},
        'status': status,
        'revision': 0,
        'updated_at': '2026-09-28T01:02:03Z',
      });

      final waiting = caseWithStatus('clinician_input_required');
      final inProgress = caseWithStatus('in_progress');
      final evaluated = caseWithStatus('evaluated');

      expect(waiting.status.label, 'Submitted — waiting for clinician');
      expect(waiting.canWithdrawSubmission, isTrue);
      expect(inProgress.status.label, 'Clinician review in progress');
      expect(inProgress.canWithdrawSubmission, isFalse);
      expect(evaluated.status.label, 'Assessment completed');
      expect(evaluated.canWithdrawSubmission, isFalse);
    },
  );
}
