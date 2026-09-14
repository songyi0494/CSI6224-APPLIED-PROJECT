import 'dart:convert';
import 'dart:io';

import 'package:csi6224_patient_feedback/models/pathway1_clinician_input.dart';
import 'package:csi6224_patient_feedback/models/pathway_evaluation.dart';
import 'package:csi6224_patient_feedback/utils/clinical_trace_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PathwayEvaluation evaluation;

  setUp(() {
    evaluation = PathwayEvaluation.fromJson(
      jsonDecode(File('test/fixtures/pathway1_result.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  ClinicalTracePresentation byRule(String ruleId) => clinicalTracePresentation(
    evaluation.trace.singleWhere((trace) => trace.ruleId == ruleId),
    clinicianInput: const Pathway1ClinicianInput(tScoreSite: 'femoral_neck'),
  );

  test(
    'T-score trace explains the clinical threshold, not raw inverse match',
    () {
      final trace = evaluation.trace.singleWhere((t) => t.ruleId == 'T_SCORE');
      expect(trace.matched, isFalse);

      final item = byRule('T_SCORE');
      expect(item.title, 'Bone density');
      expect(item.details, contains('T-score: -3.5'));
      expect(item.details, contains('Site: femoral neck'));
      expect(item.details, contains('Clinical pathway threshold: <= -2.5'));
      expect(item.result, 'Osteoporosis BMD threshold met.');
      expect(item.implication, 'Continue to recent major fracture assessment.');
      expect(item.technicalRuleId, 'T_SCORE');
    },
  );

  test('renal, frailty and recent-fracture criteria show actual values', () {
    final renal = byRule('RENAL_DYSFUNCTION');
    expect(renal.details, contains('eGFR: 54 mL/min'));
    expect(
      renal.details,
      contains('Renal referral threshold: eGFR < 30 mL/min'),
    );
    expect(renal.result, 'Renal referral criterion not triggered.');

    final frailty = byRule(
      'RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY',
    );
    expect(frailty.details, contains('Clinical Frailty Score: 4'));
    expect(frailty.details, contains('Severe frailty threshold: >= 6'));
    expect(frailty.details, contains('Life expectancy: 10 years'));
    expect(
      frailty.details,
      contains('Short life expectancy threshold: < 7 years'),
    );

    final fracture = byRule('RECENT_MAJOR_FRACTURES');
    expect(
      fracture.details,
      contains('Hip / vertebral / >=2 fractures within 24 months: Yes'),
    );
    expect(fracture.result, 'Recent major fracture criterion met.');
    expect(
      fracture.implication,
      'Consider osteoanabolic therapy and specialist referral.',
    );
  });
}
