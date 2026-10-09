import 'package:flutter/material.dart';
import '../models/live_pathway.dart';

/// Only current, valid clinician answers belonging to this assessment are shown.
/// Historical component facts and server/patient facts are not editable authority.
class ClinicianFactSummary extends StatelessWidget {
  const ClinicianFactSummary({required this.facts, super.key});
  final Map<String, Object?> facts;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Clinician-confirmed pathway information'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final entry in pathwayFactRegistry.entries)
          if (entry.value.accepts(facts[entry.key]))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_labels[entry.key] ?? entry.value.label}: ${_answer(entry.value, facts[entry.key]!)}',
                ),
              ),
            ),
      ],
    ),
  );

  static String _answer(PathwayFactDefinition definition, Object value) {
    if (value is bool) return value ? 'Yes' : 'No';
    if (definition.key == 'fractureSite' && value == 'forearm') {
      return 'Wrist / forearm';
    }
    return definition.choices[value] ?? value.toString();
  }

  static const _labels = <String, String>{
    'minimalTraumaFracture': 'Minimal trauma fracture',
    'fractureSite': 'Fracture site',
    'eGFR': 'eGFR ≥30 mL/min',
    'osteoporosisTreatmentStatus': 'Currently on osteoporosis treatment',
    'frailtyResidentialOrLimitedLifeExpectancy':
        'Residential care, severe frailty, or limited life expectancy',
    'adherenceConcern': 'Treatment-adherence concern',
    'testAvailability': 'BMD DXA available or completed within two years',
    'tScoreAtOrBelowMinus2_5AnySite':
        'T-score −2.5 or lower at a relevant site',
    'veryHighFractureRisk': 'Very high fracture risk',
    'antiresorptiveTreatmentStatus': 'Currently on antiresorptive treatment',
    'antiresorptiveTreatmentOver12Months': 'Treatment duration >12 months',
    'adheredToTheTreatment': 'Adhered to treatment',
    'symptomaticFractureInLast12M': 'Symptomatic fracture in last 12 months',
    'lowBMD': 'BMD T-score below −3.0 at any site',
    'priorMIorStroke': 'Previous myocardial infarction or stroke',
  };
}
