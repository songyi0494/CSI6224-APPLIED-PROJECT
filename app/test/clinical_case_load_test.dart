import 'dart:convert';

import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/models/clinical_case.dart';
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
      SupabaseAppRepository.clinicalCaseSelectColumns.replaceAll(' ', ''),
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
                  'assigned_clinician_id': null,
                  'clinician_facts': <String, Object?>{},
                  'pathway': null,
                  'routing_reason': null,
                  'status': 'clinician_input_required',
                  'submitted_at': '2026-09-26T01:02:03Z',
                  'updated_at': '2026-09-26T01:02:03Z',
                  'questionnaire_response_id': 'response-id',
                  'pathway_revision': 0,
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
      expect(clinicalCase.questionnaireResponseId, 'response-id');
      expect(clinicalCase.clinicianFacts, isEmpty);
      expect(clinicalCase.evaluation, isNull);
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
