import 'dart:convert';

import 'package:csi6224_patient_feedback/data/app_repository.dart';
import 'package:csi6224_patient_feedback/data/supabase_app_repository.dart';
import 'package:csi6224_patient_feedback/models/case_investigations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> investigationsJson({
  int revision = 1,
  bool completed = true,
  Object? vitaminD = 55,
  Object? ionisedCalcium = 1.2,
  Object? bodyWeight = 70,
}) => {
  'caseId': 'case-id',
  'vitaminD': {'value': vitaminD, 'unit': 'nmol/L'},
  'ionisedCalcium': {'value': ionisedCalcium, 'unit': 'mmol/L'},
  'bodyWeight': {'value': bodyWeight, 'unit': 'kg'},
  'revision': revision,
  'completed': completed,
  'completedAt': completed ? '2026-09-29T01:02:03Z' : null,
  'updatedAt': '2026-09-29T01:02:03Z',
};

SupabaseAppRepository repositoryWith(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'public-test-key',
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return SupabaseAppRepository(client);
}

void main() {
  test(
    'investigations model parses values, units, revision and completion',
    () {
      final value = CaseInvestigations.fromRpcJson(investigationsJson());

      expect(value.caseId, 'case-id');
      expect(value.vitaminDLevel, 55);
      expect(value.ionisedCalcium, 1.2);
      expect(value.bodyWeightKg, 70);
      expect(value.revision, 1);
      expect(value.isComplete, isTrue);
      expect(value.canStartPathway, isTrue);
      expect(value.completedAt, DateTime.parse('2026-09-29T01:02:03Z'));
      expect(CaseInvestigations.vitaminDUnit, 'nmol/L');
      expect(CaseInvestigations.ionisedCalciumUnit, 'mmol/L');
      expect(CaseInvestigations.bodyWeightUnit, 'kg');
    },
  );

  test('legacy revision zero fails closed and requires confirmation', () {
    final value = CaseInvestigations.fromRpcJson(
      investigationsJson(revision: 0, completed: true),
    );

    expect(value.isComplete, isFalse);
    expect(value.canStartPathway, isFalse);
    expect(value.requiresConfirmation, isTrue);
  });

  test(
    'get investigations uses the guarded RPC and parses its payload',
    () async {
      late http.Request request;
      final repository = repositoryWith((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(investigationsJson()),
          200,
          headers: {'content-type': 'application/json'},
          request: incoming,
        );
      });

      final value = await repository.getCaseInvestigations('case-id');

      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/get_case_investigations');
      expect(jsonDecode(request.body), {'p_case_id': 'case-id'});
      expect(value.canStartPathway, isTrue);
    },
  );

  test('save investigations sends every value and expected revision', () async {
    late Map<String, dynamic> body;
    final repository = repositoryWith((request) async {
      body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response(
        jsonEncode(investigationsJson(revision: 4)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });

    final value = await repository.saveCaseInvestigations(
      caseId: 'case-id',
      vitaminDLevel: 55,
      ionisedCalcium: 1.2,
      bodyWeightKg: 70,
      expectedRevision: 3,
    );

    expect(body, {
      'p_case_id': 'case-id',
      'p_vitamin_d_level': 55.0,
      'p_ionised_calcium': 1.2,
      'p_body_weight_kg': 70.0,
      'p_expected_revision': 3,
    });
    expect(value.revision, 4);
    expect(value.isComplete, isTrue);
  });

  test('stale save maps to a bounded conflict', () async {
    final repository = repositoryWith(
      (request) async => http.Response(
        jsonEncode({
          'code': 'P0001',
          'message': 'Investigations changed. Reload before saving',
          'details': null,
          'hint': null,
        }),
        400,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );

    await expectLater(
      repository.saveCaseInvestigations(
        caseId: 'case-id',
        vitaminDLevel: 55,
        ionisedCalcium: 1.2,
        bodyWeightKg: 70,
        expectedRevision: 3,
      ),
      throwsA(isA<InvestigationConflictException>()),
    );
  });

  test(
    'missing guarded RPC fails closed without a table-write fallback',
    () async {
      var requests = 0;
      final repository = repositoryWith((request) async {
        requests += 1;
        expect(request.url.path, '/rest/v1/rpc/get_case_investigations');
        return http.Response(
          jsonEncode({
            'code': 'PGRST202',
            'message':
                'Could not find the function public.get_case_investigations in the schema cache',
            'details': null,
            'hint': null,
          }),
          404,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });

      await expectLater(
        repository.getCaseInvestigations('case-id'),
        throwsA(isA<InvestigationServiceUnavailableException>()),
      );
      expect(requests, 1);
    },
  );
}
