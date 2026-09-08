# Pathway 1 Integration Contract

This checklist is for the next integration milestone between:

- Songyi: Supabase, authentication, database integration, and access control.
- Dayoung: deterministic clinical rule engine.
- Xiaomin: Flutter UI, navigation, and frontend integration.

The immediate goal is to run one synthetic Pathway 1 patient case end to end:

Login / role -> patient/questionnaire data -> clinician opens or creates a Pathway 1 case -> clinical facts entered -> case saved -> Pathway 1 evaluated -> recommendation returned -> transparent rule trace returned -> RecommendationReviewScreen displays the result -> clinician records a decision -> result is persisted.

Pathway 1 is the priority. Pathway 2 is already exposed as a Flutter UI boundary, but it should not be expanded for this milestone unless required to preserve compatibility.

## Current Implementation

Flutter source is under `/app`.

Important files:

- `/app/lib/app.dart`
- `/app/lib/data/app_repository.dart`
- `/app/lib/data/mock_app_repository.dart`
- `/app/lib/services/clinical_api_client.dart`
- `/app/lib/models/clinical_case.dart`
- `/app/lib/models/pathway_evaluation.dart`
- `/app/lib/models/questionnaire.dart`
- `/app/lib/screens/pathway_form_screen.dart`
- `/app/lib/screens/recommendation_review_screen.dart`
- `/app/test/widget_test.dart`

Current architecture:

```text
Flutter screens -> AppRepository -> concrete repository/backend implementation
```

Current concrete repository:

```dart
final MockAppRepository _repository = MockAppRepository();
```

Current evaluation entry point:

```dart
Future<PathwayEvaluation> evaluatePathway(ClinicalCase clinicalCase)
```

Current status:

- Flutter UI is implemented for the mock prototype.
- Clinician dashboard navigation is wired.
- Existing pathway drafts can reopen with pre-filled data.
- New pathway cases can be created.
- Save draft and Evaluate pathway are separate flows.
- RecommendationReviewScreen displays decisions, actions, warnings, missing inputs, unsafe inputs, and rule trace data.
- Dashboard refreshes after returning from questionnaire builder, pathway form, or recommendation review.
- Data is still in memory through `MockAppRepository`.
- Supabase is not integrated yet.
- The real deterministic rule engine is not integrated yet.

## Songyi: Supabase Integration Contract

Please integrate Supabase behind the repository layer. Do not put Supabase queries directly inside Flutter screens.

Recommended new file:

```text
/app/lib/data/supabase_app_repository.dart
```

This should implement the existing `AppRepository` interface in:

```text
/app/lib/data/app_repository.dart
```

The current Flutter UI needs these repository methods:

- `signIn`
- `fetchQuestionnaires`
- `saveQuestionnaire`
- `publishQuestionnaire`
- `fetchPatientResponses`
- `submitPatientResponse`
- `fetchClinicalCases`
- `fetchClinicalCase`
- `saveClinicalCase`
- `evaluatePathway`
- `fetchApprovedRecommendations`
- `recordClinicianDecision`

Minimum Supabase data areas needed:

- auth users
- profiles and roles
- questionnaires
- questionnaire questions, or questionnaire questions stored as JSON
- patient responses
- clinical cases
- pathway evaluation results
- clinician decisions
- approved recommendations visible to patients

Recommended tables:

- `profiles`
- `questionnaires`
- `questionnaire_questions`
- `patient_responses`
- `clinical_cases`
- `pathway_evaluations`
- `clinician_decisions`
- `approved_recommendations`

Use stable IDs in addition to display names. The current mock uses `patientName`, but Supabase should include stable identifiers such as:

- `patient_id`
- `clinician_id`
- authenticated Supabase user UUID

Suggested data model distinction:

- `clinical_cases`: stores case identity, patient, pathway, status, and clinical facts.
- `pathway_evaluations`: stores each rule-engine result, raw output, decision category, actions, trace, and timestamp.
- `clinician_decisions`: stores approve, withhold, request-more-information, or follow-up decisions.
- `approved_recommendations`: stores patient-visible approved recommendation summaries.

Required behavior to preserve:

Save draft:

- upsert the clinical case
- set status to `draft`
- preserve the same case ID when editing
- create a new case ID only for a new case
- do not run the rule engine
- return to the clinician dashboard

Evaluate pathway:

- validate the Flutter form
- upsert the clinical case
- set status to `evaluated`
- run the Pathway 1 rule engine
- persist the evaluation result
- return `PathwayEvaluation` to Flutter
- open `RecommendationReviewScreen`

Dashboard refresh:

- preserve the current repository-fetch behavior.
- after returning from the builder/form/review screen, `app.dart` rebuilds the dashboard.
- the dashboard fetches current data again through repository methods.

RLS/access control to define:

- patients can read their own questionnaire responses and approved recommendations.
- clinicians can read patient responses and clinical cases they are allowed to manage.
- clinicians can create and update clinical cases.
- clinicians can record decisions.
- patients should not directly modify clinical cases, pathway evaluations, or clinician decisions.

## Dayoung: Pathway 1 Rule Engine Contract

The current frontend evaluation input is a `ClinicalCase`.

```dart
ClinicalCase {
  id
  patientName
  pathway
  status
  facts
}
```

The rule engine mainly consumes:

```dart
clinicalCase.facts
```

Current Pathway 1 fact keys from Flutter:

| Key | Type | Required / behavior | Values or units |
| --- | --- | --- | --- |
| `osteoporosisTreatmentStatus` | bool | Required by mock check. Auto false for Pathway 1, true for Pathway 2. | true / false |
| `minimalTraumaFracture` | bool | Required by mock check. | true / false |
| `sex` | string | Required by mock check. | `female`, `male` |
| `postmenopausal` | bool | Clinically relevant mainly for female patients. | true / false |
| `age` | int | Required by form and mock check. | years |
| `fractureSite` | string | Required by mock check. | `hip`, `vertebral`, `wrist`, `humerus`, `hand`, `foot`, `face`, `ankle` |
| `eGFR` | double | Required by form and mock check. | mL/min/1.73m2, if the team accepts this unit |
| `liveInResidentialCare` | bool | Used by current mock Pathway 1 logic. | true / false |
| `clinicalFrailtyScore` | int | Required by form. Used by mock logic. | Clinical Frailty Scale score |
| `lifeExpectancy` | double | Required by form. Used by mock logic. | years |
| `knownPoorMedicationAdherence` | bool | Used by mock logic. | true / false |
| `cognitiveImpairment` | bool | Used by mock logic. | true / false |
| `testAvailable` | bool | Used by mock logic for BMD/DXA availability. | true / false |
| `testWithinLast2Years` | bool | Conditional on DXA availability. Used by mock logic. | true / false |
| `T-score` | double | Required by form. Used by mock data and should be normalized only by agreement. | lowest T-score |
| `vitaminDLevel` | double | Required by form and mock check. | unit must be agreed |
| `hipVertebralOrMultipleFracturesInLast24M` | bool | Used by mock logic as a combined recent major fracture flag. | true / false |
| `highRisk` | bool | Used by mock logic. | true / false |
| `historyOfMiOrStroke` | bool | Used as a cautionary safety flag. | true / false |

Important mismatch to resolve:

- The current mock missing-input check only requires `osteoporosisTreatmentStatus`, `minimalTraumaFracture`, `sex`, `age`, `fractureSite`, `eGFR`, and `vitaminDLevel`.
- The current Flutter Evaluate form requires all numeric fields to pass validation before evaluation.
- The team should agree whether Dayoung's required fact list should match the Flutter validators exactly.

Current frontend API adapter:

```text
/app/lib/services/clinical_api_client.dart
```

It can post:

```json
{
  "facts": {
    "osteoporosisTreatmentStatus": false,
    "minimalTraumaFracture": true,
    "sex": "female",
    "age": 74,
    "fractureSite": "hip",
    "eGFR": 54,
    "vitaminDLevel": 65
  }
}
```

This adapter exists, but it does not decide the final architecture. The team still needs to agree whether the rule engine will be local deterministic Dart/JSON logic, a Supabase Edge Function, or another HTTP API.

## Rule-Engine Output Contract

The deterministic rule engine must return more than a final recommendation. It must return enough information to support a transparent clinical reasoning trace.

Current frontend can parse this response shape:

```json
{
  "pathway": "PATHWAY1",
  "decision": "action_taken",
  "actions": [
    {
      "type": "referral",
      "destination": "FRAGILE BONE CLINIC",
      "reason": "Recent major fracture risk"
    }
  ],
  "trace": [
    "ENTRY_CONDITION_PASSED",
    "RECENT_MAJOR_FRACTURES"
  ]
}
```

Minimum required output:

- `pathway`
- `decision`
- `actions`
- `trace`
- missing information where relevant

Decision strings already displayed by Flutter:

- `action_taken`
- `needs_more_information`
- `requires_rule_engine`
- `not_applicable`

Action shapes already supported by Flutter:

- `recommendation`
- `medication`, `dose`, `route`, `frequency`
- `destination`, `reason`
- `action`
- `instruction`
- `targetPathway`
- `options`

Recommended future trace format:

```json
{
  "ruleId": "P1_ENTRY_MINIMAL_TRAUMA",
  "condition": "minimalTraumaFracture == true",
  "passed": true,
  "reason": "Patient has minimal trauma fracture"
}
```

For the first Pathway 1 integration, a simple string trace is acceptable if it is transparent enough for RecommendationReviewScreen.

## Recommended Design Improvements

- Keep `MockAppRepository` for local testing and development.
- Add `SupabaseAppRepository` as a separate implementation.
- Store pathway evaluations separately from clinician decisions.
- Treat `patientName` as display text, not the primary database link.
- Use stable IDs for patients, clinicians, cases, responses, evaluations, and decisions.
- Consider renaming `T-score` to `tScore` only if Flutter, Supabase, and the rule engine all change together.
- Add dedicated integration tests after Supabase and rule engine are connected.

## Agreement Required Before Integration

- Final Supabase table names.
- Whether questionnaire questions are separate rows or stored as JSON.
- Whether IDs are generated by Supabase UUIDs or passed from Flutter.
- Exact role mapping for `patient` and `clinician`.
- Whether `patient_name` remains display-only and `patient_id` becomes the real link.
- Exact enum strings for pathway, case status, questionnaire status, question type, and rule decision.
- Whether `T-score` stays as-is or changes to `tScore`.
- Units for eGFR, vitamin D, frailty score, and life expectancy.
- Required vs optional clinical facts for Pathway 1.
- Missing-value behavior.
- Rule-engine architecture: local Dart, Supabase Edge Function, HTTP API, or other.
- Rule request shape: facts only or full clinical case.
- Rule response shape.
- Rule trace format.
- Whether every evaluation is persisted.
- Whether clinician decisions are separate from clinical case status.
- RLS rules for patients, clinicians, and future admin users.

## Do Not Change During Integration

- Do not add Supabase queries directly inside Flutter screen widgets.
- Do not remove `MockAppRepository` unless the team intentionally replaces it for all environments.
- Do not merge Save draft and Evaluate pathway.
- Do not make Save draft run the rule engine.
- Do not expand Pathway 2 scope for this milestone.
- Do not change patient response display behavior unless separately agreed.
- Do not rename current fact keys without coordinating Flutter, Supabase, and rule engine changes together.

## Pathway 1 Acceptance Checklist

- [ ] User can log in with role-based access.
- [ ] Patient/questionnaire sample data is available from Supabase or agreed seed data.
- [ ] Clinician can open an existing Pathway 1 case.
- [ ] Clinician can create a new Pathway 1 case.
- [ ] Save draft persists the case without running the rule engine.
- [ ] Reopening a draft loads the same case ID and pre-fills clinical facts.
- [ ] Evaluate pathway saves the case and runs the Pathway 1 rule engine.
- [ ] Rule engine receives the agreed clinical facts.
- [ ] Rule engine returns decision, actions/recommendation, and transparent trace.
- [ ] `RecommendationReviewScreen` displays the returned recommendation.
- [ ] `RecommendationReviewScreen` displays trace information.
- [ ] Clinician can record approve, withhold, request-more-information, or follow-up decision.
- [ ] Clinician decision is persisted.
- [ ] Approved recommendation can be made visible to the patient where applicable.
- [ ] Dashboard refreshes after returning from form/review screens.
- [ ] One synthetic Pathway 1 patient case works end to end.
