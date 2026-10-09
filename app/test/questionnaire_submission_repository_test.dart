import 'dart:convert';

import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:csi6224_patient_feedback/models/questionnaire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const patient = '40000000-0000-4000-8000-000000000001';
const response = '40000000-0000-4000-8000-000000000002';
const visibleAnswers = <String, Object?>{
  'postmenopausal': 'No',
  'smoking': 'No',
  'alcohol': 'No',
  'dairyLessThan3Serves': true,
};

void main() {
  for (final gender in ['female', 'male']) {
    test(
      '$gender submission saves visible answers with authoritative profile sex',
      () async {
        Map<String, dynamic>? saved;
        var submitted = false;
        final calls = <String>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'public-test-key',
          httpClient: MockClient((request) async {
            calls.add('${request.method} ${request.url.path}');
            Object? body;
            if (request.url.path.endsWith('/token')) {
              body = {
                'access_token':
                    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJleHAiOjQxMDI0NDQ4MDB9.synthetic',
                'refresh_token': 'synthetic-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': patient,
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': 'synthetic@example.test',
                },
              };
            } else if (request.url.path.endsWith('/profiles')) {
              body = {'gender': gender};
            } else if (request.url.path.endsWith(
              '/submit_questionnaire_response',
            )) {
              expect(jsonDecode(request.body), {'p_response_id': response});
              expect(saved, isNotNull);
              submitted = true;
              body = 'case-id';
            } else if (request.url.path.endsWith('/questionnaire_responses')) {
              if (request.method == 'POST') {
                saved = jsonDecode(request.body) as Map<String, dynamic>;
              }
              body = saved == null
                  ? <Object?>[]
                  : {
                      'id': response,
                      'patient_id': patient,
                      'answers': saved!['answers'],
                      'status': submitted ? 'submitted' : 'draft',
                      'revision': 1,
                      'submitted_at': submitted ? '2026-10-09T01:00:00Z' : null,
                    };
            } else {
              throw StateError('Unexpected test request');
            }
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'synthetic@example.test',
          password: 'synthetic',
        );
        final value = await SupabaseAppRepository(client)
            .submitQuestionnaireResponse(
              answers: {
                ...visibleAnswers,
                'sex': gender == 'female' ? 'Male' : 'Female',
              },
            );
        expect(value.status, QuestionnaireResponseStatus.submitted);
        final persisted = saved!['answers'] as Map<String, dynamic>;
        expect(persisted['sex'], gender == 'female' ? 'Female' : 'Male');
        expect(
          persisted.keys.toSet(),
          gender == 'female'
              ? {...visibleAnswers.keys, 'sex'}
              : {'sex', 'smoking', 'alcohol', 'dairyLessThan3Serves'},
        );
        expect(
          calls.indexOf('POST /rest/v1/questionnaire_responses'),
          lessThan(
            calls.indexOf('POST /rest/v1/rpc/submit_questionnaire_response'),
          ),
        );
      },
    );
  }
  for (final backendMessage in [
    'All required questionnaire questions must be answered',
    'Internal failure for $patient synthetic@example.test eyJsecret SQL secret-value',
  ]) {
    test(
      'submission failure retains safe patient message and bounded diagnostics: ${backendMessage.startsWith('All')}',
      () async {
        final diagnostics = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) diagnostics.add(message);
        };
        addTearDown(() => debugPrint = original);
        final client = SupabaseClient(
          'https://example.supabase.co',
          'public-test-key',
          httpClient: MockClient((request) async {
            Object? body;
            var status = 200;
            if (request.url.path.endsWith('/token')) {
              body = {
                'access_token':
                    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJleHAiOjQxMDI0NDQ4MDB9.synthetic',
                'refresh_token': 'synthetic-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': patient,
                  'aud': 'authenticated',
                  'role': 'authenticated',
                },
              };
            } else if (request.url.path.endsWith('/profiles')) {
              body = {'gender': 'female'};
            } else if (request.url.path.endsWith(
              '/submit_questionnaire_response',
            )) {
              body = {
                'message': backendMessage,
                'code': 'P0001',
                'details': null,
                'hint': null,
              };
              status = 400;
            } else {
              body = request.method == 'GET'
                  ? <Object?>[]
                  : {
                      'id': response,
                      'patient_id': patient,
                      'answers': visibleAnswers,
                      'status': 'draft',
                      'revision': 1,
                    };
            }
            return http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'synthetic@example.test',
          password: 'synthetic',
        );
        await expectLater(
          SupabaseAppRepository(
            client,
          ).submitQuestionnaireResponse(answers: visibleAnswers),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              'Your questionnaire could not be submitted. Your answers remain on this screen so you can retry.',
            ),
          ),
        );
        expect(
          diagnostics,
          contains(
            'QUESTIONNAIRE SUBMIT ERROR: reason=${backendMessage.startsWith('All') ? 'missing_active_answer' : 'backend_failure'}',
          ),
        );
        final output = diagnostics.join('\n');
        for (final sensitive in [
          patient,
          'synthetic@example.test',
          'eyJsecret',
          'SQL',
          'secret-value',
        ]) {
          expect(output, isNot(contains(sensitive)));
        }
        expect(visibleAnswers['smoking'], 'No');
      },
    );
  }
}
