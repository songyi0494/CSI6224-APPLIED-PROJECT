# Frontend Integration Contract

This document separates the Flutter UI responsibilities from Supabase and rule-engine responsibilities for the CSI6224 prototype.

## Branching

- Base branch: `develop`
- Frontend branch: `feature/flutter-ui-integration-xiaomin`
- Do not push directly to `master`; it is protected.

## Flutter Ownership

Xiaomin owns:

- `/app` Flutter project structure for Web and Android.
- Role-based entry flow for patient and clinician users.
- Patient questionnaire and approved recommendation views.
- Clinician dashboard, questionnaire builder placeholder, patient response review, Pathway 1/2 input form, recommendation review, and decision recording.
- Mock repository so UI development can continue before Supabase is ready.
- Final integration checks across Flutter UI, Supabase Auth/database, and rule-engine outputs.

## Supabase Inputs Needed By Flutter

The Flutter app needs these values from the Supabase team:

- Supabase project URL.
- Anon key for the prototype client.
- Auth role strategy: `patient` and `clinician`.
- Row-level security rules for patient-owned records and clinician review access.
- Edge Function URL for `evaluate_pathway_1`.
- Table names and columns for questionnaires, questionnaire responses, clinical cases, recommendations, and clinician decisions.

## Pathway 1 Edge Function Request

The current frontend maps the clinical form into the same fact names used by `code/supabase/functions/evaluate_pathway_1/pathway_1.json`.

```json
{
  "facts": {
    "osteoporosisTreatmentStatus": false,
    "minimalTraumaFracture": true,
    "sex": "female",
    "postmenopausal": true,
    "age": 74,
    "fractureSite": "hip",
    "eGFR": 54,
    "liveInResidentialCare": false,
    "clinicalFrailtyScore": 4,
    "lifeExpectancy": 10,
    "knownPoorMedicationAdherence": false,
    "cognitiveImpairment": false,
    "testAvailable": true,
    "testWithinLast2Years": true,
    "T-score": -2.7,
    "hipVertebralOrMultipleFracturesInLast24M": true,
    "highRisk": true
  }
}
```

## Pathway Evaluation Response

Flutter expects this response shape:

```json
{
  "pathway": "PATHWAY1",
  "decision": "action_taken",
  "actions": [
    {
      "type": "consideration",
      "recommendation": "Consider commencement of osteoanabolic therapy",
      "requireReview": true
    }
  ],
  "trace": [
    "ENTRY_CONDITION_PASSED",
    "RECENT_MAJOR_FRACTURES"
  ]
}
```

## Integration Issues To Resolve

- The root README previously mentioned Firebase. The team has moved to Supabase, so all docs should use Supabase consistently.
- `pathway_1.json` contains one `postmenopausal` value as the string `"true"` in the entry condition. Flutter sends a boolean `true`.
- `pathway_1.json` repeats the rule id `RECENT_MAJOR_FRACTURES`. Unique ids will make the rule trace easier to explain in the final demo.
- Pathway 2 has UI coverage in Flutter, but a Supabase Edge Function for Pathway 2 is still required.
- The edge function currently imports `createClient` but does not use it. That can be removed or used when database persistence is added.

## Final Demo Checklist

- Clinician signs in and opens dashboard.
- Clinician reviews a submitted patient questionnaire response.
- Clinician creates or opens a Pathway 1 case.
- Clinician enters clinical facts and runs the evaluation.
- App displays recommendation actions and transparent rule trace.
- Clinician approves, withholds, or requests more information.
- Patient signs in and sees approved recommendations only.
- Web build and Android debug build both complete.
