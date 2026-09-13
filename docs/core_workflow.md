# Core workflow implementation

## Architecture

Flutter screens → AppRepository → SupabaseAppRepository → authenticated RPCs / Edge Function → PostgreSQL.

MockAppRepository independently implements the same interface using synthetic, in-memory data. Its local development HTTP service imports the same TypeScript engine and JSON as the deployed Edge Function. It is not a persistence substitute and must never handle real patient data.

The patient sends an assessment UUID, expected revision and structured input to save_assessment. Identity comes from auth.uid(), never the supplied patient name. Evaluation accepts only an assessment ID and revision; the Edge Function verifies the user, retrieves owned stored facts, runs the engine and persists through a service-role-only RPC. It returns no raw recommendation to the patient.

Approved clinicians can review the shared unassigned queue; after a decision, the assessment belongs to that clinician's queue. This is the explicit initial care-access policy, not a multi-organisation tenancy model. A decision atomically records the reviewer, evaluation, revision, time and notes. A request for more information reopens the same assessment and appends immutable input/evaluation revisions. Approval requires a current actionable Pathway 1 evaluation. Only an approved decision tied to that current evaluation exposes actions to the patient.

## Local synthetic demonstration

Requires Node 24+ and Flutter 3.44+ / Dart 3.12+. From code:

```sh
npm ci
npm test
npm run dev
```

In a second terminal, from app:

```sh
flutter pub get
flutter run -d chrome --dart-define=APP_MODE=mock
```

The development engine listens on localhost:8787. This default is intended for a browser on the same computer. Device/emulator loopback configuration is not included. Mock storage resets when the repository instance restarts.

Synthetic accounts all use DemoPass123!: patient@example.test, treated@example.test, clinician@example.test, pending@example.test, rejected@example.test, admin@example.test. The first two own different drafts. The treated patient routes to Pathway 2. These accounts are not seeded into Supabase.

## Database preflight and deployment

No external Supabase schema was accessible during implementation. No remote migration was applied. Existing dashboard resources must be inspected before deployment; do not infer compatibility from an existing Auth setup or profiles table.

1. Export the existing schema, functions, policies, grants and auth provisioning triggers through an authorised operator. code/supabase/preflight.sql is a read-only structure inventory, not a complete backup. Review the full definitions of any existing functions/triggers and reuse valid structures.
2. If any of profiles, assessments, clinical_inputs, evaluations or clinician_decisions already exists, the baseline deliberately fails. Prepare a reviewed incremental reconciliation migration instead of dropping tables or bypassing the guard. Existing auth users also need a reviewed profile backfill: the new trigger provisions only new users.
3. On a verified fresh development schema, use the Supabase CLI from code to link the intended development project and apply the checked-in migrations. Review `supabase db push --dry-run` before `supabase db push`. For a local Supabase instance, initialise its local configuration as required by the installed CLI, then use local migrations. The checked-in config contains only project/function settings, not a full local service configuration.
4. Deploy evaluate_pathway_1 from code with `supabase functions deploy evaluate_pathway_1`. The Edge runtime uses SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY. Keep the service-role key exclusively on the backend. Gateway JWT verification remains enabled. Verify gateway compatibility with the project's signing configuration in live acceptance.
5. Configure Auth email confirmation and valid redirect URLs for the actual app host. Register the first account normally, verify its identity, then have a privileged operator promote that exact profiles.id to admin and clear approval_status. Do not grant admin from signup metadata. Record the operator change in the deployment record. No public admin registration or automatic admin seed exists.
6. Run the app with public connection information only:

```sh
flutter run -d chrome --dart-define=APP_MODE=supabase \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

APP_MODE has no implicit mock fallback. Supabase failures are shown as errors. Authentication state changes and foreground/profile refresh reset protected navigation. Backend roles and RLS guard every operation independently of UI state. MFA has a session-assurance boundary only; a challenge/enrolment UI is not implemented.

## Data and clinical contract

Five core tables are versioned with RLS: profiles, assessments, clinical_inputs, evaluations, clinician_decisions. Patient inputs preserve null/unknown values. ClinicalInput owns the Dart-to-rule field mapping. Dates of birth prefill age; eGFR is not converted to creatinine clearance. Input ownership and authorisation always use UUIDs.

The existing JSON remains the clinical source, with only boolean typing and duplicate rule IDs corrected. Thresholds and medication actions were not clinically redefined. The engine stops only when a stopping rule matches. Relevant unknown/type-invalid input produces a missing-input result with no partial recommendation. Previous treatment routes to Pathway 2 without running Pathway 1; unknown treatment does not select either route.

The clinical contract is provisional: the project's clinician must confirm definitions and units, especially isRobustWoman, vitamin D and renal measures. isRobustWoman is not collected under an invented patient-facing question; a branch requiring it therefore remains incomplete/manual review. The JSON commonAdvice/investigations sections are not executed by this rule evaluator. They require an agreed integration contract before being presented as complete pathway coverage. Test fixtures are synthetic examples, not clinical approval or proof of treatment safety.

Clinician notes are explicitly patient-visible, including requests, withholding and follow-up details. Automated unapproved actions/trace remain hidden from patients. Notification is currently an in-app status/notes workflow on reload; email, push notifications and background result subscriptions are not implemented. Follow-up stores an action and notes; it does not schedule an appointment. Questionnaire authoring remains available in mock mode only and is outside the five-table persistence milestone.

## Verification and acceptance

Backend: `cd code && npm ci && npm test`. Tests exercise the actual engine, handler source with auth/network test doubles, and the actual migration/RLS/functions in PGlite PostgreSQL. The database is closed and reopened to verify persistence. This is not a live Supabase Auth, REST or Edge gateway test.

Flutter checks to run on a supported host:

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build web --dart-define=APP_MODE=mock
```

Widget tests use mock repositories and fixtures generated by the engine; they do not prove production integration. The lockfile is reused from the repository's DB_setup branch, with the matching Supabase dependency constraint; fresh pub resolution remains required.

Live acceptance requires separate patient and clinician browser sessions: patient signup/email verification → structured submission → stored input/evaluation → clinician approval by admin → approved clinician reads that same assessment/trace → requests more information → patient revises the same UUID → clinician reloads and approves → patient sees only current approved actions → restart/relogin preserves the result. Also test another patient, pending/rejected clinician, stale review, duplicate submit, invalid session, logout/back navigation, Pathway 2/manual review, withhold and follow-up. Inspect network/RLS responses, not only visible screens.

## Verification limits for this delivery

Local backend suite: 32 passing, zero failing (includes a database parent test). Native Dart/Flutter execution was blocked by sandbox denial of CPU-information access during VM startup. Therefore pub get, analyzer, Flutter tests, web build and rendered UI acceptance were not run. WASM Dart formatting/parser checks verify syntax only, not types or layout. The external Supabase implementation was unavailable: deployment, email delivery, hosted RLS and cross-session end-to-end acceptance remain blocked until an authorised project environment is available.
