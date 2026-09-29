# Songyi UX/UI Phase 3A — Live Backend Authority Inventory

**Audit date:** 2026-09-29
**Audit mode:** Read only
**Repository:** `songyi0494/CSI6224-APPLIED-PROJECT`
**Branch:** `implementation/osteocare-pathway`
**Baseline HEAD:** `381d18487d58fad9bb254eeec6a7ad8c7455b369`
**Live Supabase project:** `cwxxumfmvmspofouqxxh`

## A. Audit result

**SONGYI PHASE 3A LIVE BACKEND AUTHORITY: PASS**

The deployed schema, policies, grants, SQL functions, triggers, and current
`evaluate_pathway` Edge Function were inspected read-only. No patient records
were queried.

- Existing Phase 1/2 working-tree changes were preserved.
- Xiaomi repository used: **NO**

## B. Live project

**project:** `cwxxumfmvmspofouqxxh`

All six live public tables have RLS enabled. No public views or materialized
views exist.

## C. Live table inventory

### `clinical_cases`

- PK: `id uuid`, default `gen_random_uuid()`
- FKs:
  - `patient_id -> profiles.id`, cascade delete
  - `assigned_clinician_id -> profiles.id`, set null
  - `questionnaire_response_id -> questionnaire_responses.id`, restrict delete
- Unique: `questionnaire_response_id`
- Relevant columns:
  - `patient_id uuid NOT NULL`
  - `assigned_clinician_id uuid NULL`
  - `clinician_facts jsonb NOT NULL DEFAULT '{}'`
  - `pathway text NULL`, check `PATHWAY1|PATHWAY2`
  - `routing_reason text NULL`
  - `status text NOT NULL DEFAULT 'draft'`
  - `submitted_at`, `claimed_at`, `created_at`, `updated_at timestamptz`
  - `results_review jsonb NOT NULL DEFAULT '{}'`
  - `rule_evaluation jsonb NULL`
  - `questionnaire_response_id uuid NULL`
  - `pathway_revision integer NOT NULL DEFAULT 0`, check `>= 0`
  - `pathway_answer_order text[] NOT NULL DEFAULT '{}'`
- Status check allows only:
  - `draft`
  - `clinician_input_required`
  - `in_progress`
  - `evaluated`

### `investigations`

- PK: `id uuid`, default `gen_random_uuid()`
- FKs:
  - `case_id -> clinical_cases.id`, cascade delete
  - `entered_by -> profiles.id`, restrict delete
- Unique: `case_id`
- Relevant columns:
  - `vitamin_d_level numeric NULL`, non-negative check
  - `total_calcium numeric NULL`, non-negative check
  - `ionised_calcium numeric NULL`, non-negative check
  - `phosphate numeric NULL`, non-negative check
  - `tsh numeric NULL`
  - `body_weight_kg numeric NULL`, positive check
  - `t_score numeric NULL`
  - `test_date date NULL`
  - `completed_at timestamptz NULL`
  - `created_at`, `updated_at timestamptz NOT NULL`
- No status column.
- No revision/version column.
- Update trigger changes `updated_at` only.
- No column comments or metadata define laboratory units.

### `clinician_decisions`

- PK: `id uuid`, default `gen_random_uuid()`
- FKs:
  - `case_id -> clinical_cases.id`, cascade delete
  - `clinician_id -> profiles.id`, restrict delete
- Unique: `case_id`
- Relevant columns:
  - `decision text NOT NULL`, check `approved|rejected`
  - `notes text NULL`
  - `pathway_revision integer NOT NULL`, check `>= 0`
  - `created_at`, `updated_at timestamptz NOT NULL`
- No approved-action snapshot.
- No Common Advice snapshot.
- No explicit patient-release marker.
- No dedicated `reviewed_at`; timestamps are generic.

### `profiles`

- PK/FK: `id uuid -> auth.users.id`, cascade delete
- Relevant columns:
  - `role text NOT NULL`, check `patient|clinician|admin`
  - `full_name text NULL`
  - `date_of_birth date NULL`
  - `gender text NULL`
  - `approval_status text NOT NULL DEFAULT 'approved'`
  - `approval_reviewed_by uuid NULL -> profiles.id`
  - `approval_reviewed_at timestamptz NULL`
  - timestamps

### `questionnaire_responses`

- PK: `id uuid`
- FK: `patient_id -> profiles.id`, cascade delete
- Unique: `patient_id`
- Relevant columns:
  - `answers jsonb NOT NULL DEFAULT '{}'`, object check
  - `status text NOT NULL DEFAULT 'draft'`, check `draft|submitted`
  - `revision integer NOT NULL DEFAULT 1`, check `>= 1`
  - `submitted_at`, `created_at`, `updated_at`
- Trigger increments `revision` when `answers` changes.

### `questionnaire_questions`

- PK: `id uuid`
- FK: `created_by -> profiles.id`, restrict delete
- Relevant columns:
  - `question_text`
  - `question_type`, constrained to supported types
  - `options jsonb`
  - `is_required`
  - `display_order`
  - `field_key text UNIQUE`
  - timestamps

There is no separate evaluation, approved-result, recommendation, release, or
Common Advice table.

## D. Live function / RPC inventory

| Function | Contract and authorization | Writes |
|---|---|---|
| `submit_questionnaire_response(uuid) -> uuid` | Patient role; owned draft response; locks response; validates required live questions | Marks response submitted and creates `clinician_input_required` case |
| `claim_clinical_case(uuid) -> void` | Clinician role, but does **not** check clinician approval; requires unassigned `clinician_input_required` case | Assigns caller, sets `in_progress`, sets `claimed_at`; no revision increment |
| `save_pathway_answer(uuid,text,jsonb) -> jsonb` | Approved assigned clinician; case `in_progress`; requires an investigation row with non-null `completed_at` | Updates facts/order, clears old evaluation/pathway, increments `pathway_revision` |
| `get_pathway_case_context(uuid) -> jsonb` | Approved assigned clinician; case `in_progress` | None |
| `save_rule_evaluation(uuid,jsonb) -> void` | Approved assigned clinician; case `in_progress`; validates complete evaluator structure | Stores evaluation, pathway and routing reason; sets `evaluated` |
| `get_rule_evaluation(uuid) -> jsonb` | Admin, assigned approved clinician, or owning patient with current approved decision | None |
| `review_pathway_evaluation(uuid,text,text) -> void` | Approved assigned clinician; evaluated case; evaluation revision must equal current case revision; accepts only `approved|rejected` | Upserts decision; rejection returns case to `in_progress` |
| `review_clinical_case_results(uuid) -> void` | Approved assigned clinician; case `in_progress`; reads questionnaire, investigations and DOB | Writes `results_review`; sets `investigations.completed_at` |
| `set_clinical_case_pathway(uuid,text) -> void` | Clinician role; assigned `in_progress` case with no pathway | Sets pathway; no investigation check |
| `is_approved_clinician() -> boolean` | Checks clinician role and approved profile status | None |

The business RPCs above are `SECURITY DEFINER`; mutation RPCs were not invoked.

## E. Deployed evaluator

The deployed `evaluate_pathway` bundle was inspected directly.

- Dashboard showed:
  - **Deployments:** `21`
  - **Last deployed:** approximately 20 hours before this audit
  - No artifact SHA was exposed.
- Request: authenticated JSON body containing exactly `{"caseId": "<uuid>"}`
- Preconditions inherited from `get_pathway_case_context`:
  - authenticated caller
  - approved clinician
  - assigned clinician
  - case status `in_progress`
- Initial pathway: always `PATHWAY1`
- Data read: `clinical_cases.clinician_facts`, pathway answer order,
  assignment, status and revision through the context RPC
- Data written on completion: `clinical_cases.rule_evaluation`, pathway,
  routing reason and status through `save_rule_evaluation`
- Rules are embedded JSON, not live database rows.

Deployed fact keys are limited to the clinical pathway facts such as eGFR,
treatment status, frailty, life expectancy, adherence, cognitive impairment,
test availability, T-scores, fracture-risk facts, FRAX values, prior MI/stroke
and denosumab sequencing.

Question response:

- `status: "question"`
- `pathwayId`
- `nodeId`
- `question`
- `requiredFacts`
- `trace`

Complete response:

- `status: "complete"`
- `pathwayId`
- `actions`
- `trace`

The deployed evaluator does **not** read or reference:

- Vitamin D
- Ionised calcium
- Body weight
- `investigations`
- questionnaire responses
- Common Advice
- sex
- postmenopausal status
- dairy
- smoking
- alcohol

It also does not perform an investigation gate before saving a complete
evaluation.

## F. Investigations

**INVESTIGATIONS STORAGE: PARTIAL**

| Field | Exists live? | Table/key | Type | Unit encoded? | Nullable | Clinician writable? |
|---|---|---|---|---|---|---|
| Vitamin D | Yes | `investigations.vitamin_d_level` | `numeric` | No | Yes | Yes, assigned approved clinician while case is `in_progress` |
| Ionised calcium | Yes | `investigations.ionised_calcium` | `numeric` | No | Yes | Yes, same restriction |
| Body weight | Yes | `investigations.body_weight_kg` | `numeric` | Yes: kg in key | Yes | Yes, same restriction |

Reusable live elements:

- One investigation record per case
- Case and clinician linkage
- Required three storage columns
- Test date, completion timestamp and audit timestamps
- Clinician-scoped RLS

Missing or weak elements:

- No laboratory unit authority for Vitamin D or ionised calcium
- No investigation revision/version
- No expected-revision save contract
- `completed_at` is directly writable and is not constrained to required-value completeness
- No dedicated server-validated save/read RPC
- No complete end-to-end pathway gate

## G. Investigation units

**UNIT CONTRACT: UNRESOLVED**

`body_weight_kg` explicitly encodes kilograms. Neither Vitamin D nor ionised
calcium has a column comment, metadata record, unit constraint, or authoritative
server validation identifying its unit.

Thresholds in `review_clinical_case_results` are not sufficient authority to
infer units.

## H. Pathway gate

**CURRENT SERVER-SIDE INVESTIGATION GATE: NO**

Current behavior:

- `claim_clinical_case`: no investigation check.
- `set_clinical_case_pathway`: no investigation check.
- `save_pathway_answer`: checks only that `investigations.completed_at` is non-null.
- `get_pathway_case_context`: no investigation check.
- Deployed `evaluate_pathway`: no investigation check.
- `save_rule_evaluation`: no investigation check.

The current `save_pathway_answer` check is a partial guard, not an end-to-end
gate. Trusted boundaries requiring reconciliation are:

1. Claim/start boundary
2. Evaluation context boundary
3. Final evaluation persistence boundary

## I. Age

**AGE CONTRACT: SERVER-COMPUTED AGE CONTRACT REQUIRED**

Assigned clinicians cannot directly read the patient's
`profiles.date_of_birth` under current profile RLS.

The live `review_clinical_case_results` RPC already demonstrates the correct
server calculation:

```sql
extract(year from age(current_date, date_of_birth))
```

However, that RPC is side-effecting, investigation-dependent, and does not
provide a bounded read contract for the clinician case overview. A
minimum-disclosure server projection/RPC is still required.

## J. Final decision

| Capability | Exists live? | Authority |
|---|---|---|
| Approve persisted | Yes | `review_pathway_evaluation(..., 'approved', ...)` and `clinician_decisions` |
| Withhold persisted | No | Only `rejected` exists; it returns the case to `in_progress` and must not be assumed equivalent |
| Reviewer persisted | Yes | `clinician_decisions.clinician_id` |
| Decision timestamp | Partial | Generic `created_at`/`updated_at`; no dedicated reviewed/approved timestamp |
| Clinician message | Partial | `notes` exists, but no patient-message/release contract |
| Approved actions snapshot | No | Evaluation remains in `clinical_cases.rule_evaluation` |
| Patient release marker | No | Approval is inferred through a matching decision row |

Approval guards correctly require:

- assigned approved clinician
- evaluated status
- non-null evaluation
- evaluation `pathwayRevision` matching the current case revision

## K. Patient result release

**PATIENT APPROVED-RESULT RELEASE: PARTIAL**

What exists:

- `get_rule_evaluation` releases the raw evaluation to the owning patient only
  when:
  - case status is `evaluated`
  - a decision is `approved`
  - reviewer matches the assigned clinician
  - decision revision equals current case revision

What is missing:

- No patient-safe approved-result projection
- No immutable approved recommendation snapshot
- No approved Common Advice snapshot
- No explicit release marker or release timestamp
- No dedicated clinician-message projection

Additional risk: patients can select their own `clinical_cases` row, and
`results_review` is among the granted columns. Therefore generated investigation
advice can be API-readable independently of the approval decision, even though
the current Flutter client does not request it.

## L. Common Advice

**COMMON ADVICE GENERATION: YES**

Source: `review_clinical_case_results`.

It generates:

- Vitamin D recommendation
- Calcium recommendation
- Age-dependent protein recommendation
- A fixed lifestyle advice array

**COMMON ADVICE STORAGE: YES**

Stored in `clinical_cases.results_review`.

**COMMON ADVICE RETURNED TO FLUTTER: NO**

The current Flutter live repository does not select `results_review` and does
not invoke `review_clinical_case_results`. The displayed `Common Advice` is
static client text, not backend output.

### Verified input mapping

| Proposed input | Live use |
|---|---|
| Vitamin D | VERIFIED INPUT |
| Ionised calcium | VERIFIED INPUT |
| Body weight | VERIFIED INPUT, only when calculated age is at least 65 |
| Sex | NOT USED |
| Postmenopausal | NOT USED |
| Dietary dairy servings | VERIFIED INPUT |
| Smoking | NOT USED |
| Alcohol | NOT USED |
| Pathway result | NOT USED |

The lifestyle advice is static; it is not conditional on the stored smoking or
alcohol answers.

## M. RLS / authorization

All six public tables have RLS enabled. `Admin` below means an authenticated
`profiles.role = admin`, not service-role/Postgres bypass.

| Resource | Patient | Clinician | Admin |
|---|---|---|---|
| `profiles` | Read own; update own limited profile fields | Read/update own only; cannot read assigned patient DOB | Read all; no broad direct update policy |
| `clinical_cases` | Read own; no write | Read unassigned queue/assigned cases through permitted columns; mutations through RPCs | No broad direct policy |
| `investigations` | No read/write | Approved assigned clinician can read/insert/update while case is `in_progress` | Read; no broad direct write |
| `questionnaire_responses` | Read own; insert and update own draft answers | Approved clinician can read submitted response linked to an accessible case | Read all; no direct write |
| `clinician_decisions` | No direct read/write | Approved assigned clinician can read; write through decision RPC | Read; no broad direct write |
| `questionnaire_questions` | Authenticated read | Read; approved clinician may manage custom rows only | Read; may manage custom rows |

Notable authorization gap: `claim_clinical_case` checks clinician role but not
`approval_status`.

## N. Revision safety

| Area | Current protection | Gap |
|---|---|---|
| Questionnaire response | Trigger increments revision when answers change; submission locks row | Client writes have no expected-revision comparison |
| Clinical pathway answers | Row lock; increments `pathway_revision`; downstream answers/evaluation cleared | No expected revision argument, so stale clients are not rejected explicitly |
| Investigations | Timestamp trigger only | No revision or stale-write protection |
| Evaluation | Context returns revision | Edge Function does not submit an expected revision; stale evaluation can be stamped with the latest revision by `save_rule_evaluation` |
| Approval | Locks case and requires evaluation revision equal current case revision | Cannot detect a stale computation already stamped with the current revision; decision row can be overwritten |
| Approved result | Decision records pathway revision | No immutable versioned snapshot of released actions/advice |

The backend only partially prevents approval of obsolete evaluation output.

## O. Phase 3 contract reconciliation

| Provisional item | Classification |
|---|---|
| Case-linked investigations storage | NOT REQUIRED — LIVE ALREADY SUPPORTS |
| Three-value completion state | NEEDS MODIFICATION |
| Claim gate | BACKEND EXTENSION REQUIRED |
| Evaluate gate | BACKEND EXTENSION REQUIRED |
| Server-computed age | NEEDS MODIFICATION |
| Approve persistence | NOT REQUIRED — LIVE ALREADY SUPPORTS |
| Withhold persistence | BACKEND EXTENSION REQUIRED |
| Approved recommendation snapshot | BACKEND EXTENSION REQUIRED |
| Patient release projection | NEEDS MODIFICATION |
| Common Advice generation | NEEDS MODIFICATION |
| Common Advice approved snapshot | BACKEND EXTENSION REQUIRED |
| Revision safety | NEEDS MODIFICATION |

## P. Schema change

**SCHEMA CHANGE REQUIRED: PARTIAL**

Existing `investigations`, `clinician_decisions`,
`clinical_cases.results_review`, and `pathway_revision` structures should be
reused.

Minimal additive storage needs are:

- Investigation revision/version support
- A versioned approved-result snapshot containing released actions and approved
  Common Advice
- Explicit release/review timestamp or marker
- Exact Withhold state only after its semantics are approved

Age access and pathway gates can be implemented through constrained server
contracts without duplicating stored patient data.

## Q. Minimum backend extension

| Capability | Live current state | Reuse existing? | Missing backend work |
|---|---|---|---|
| Investigations storage | Three values already present | Yes | Establish authoritative lab units and revision |
| Investigations save/read | Direct RLS access | Yes | Validated server contract with expected revision |
| Investigations completion | `completed_at` exists | Yes | Atomic completeness validation; prevent arbitrary completion |
| Pathway start gate | Only pathway-answer save checks completion marker | Partial | Gate claim/context/evaluation persistence |
| Age access | DOB hidden; existing side-effecting function computes age | Partial | Read-only server-computed age projection |
| Approve | Persisted as `approved` | Yes | Connect client to verified live RPC |
| Withhold | No; only `rejected` | No | Approve exact semantics and extend decision contract |
| Clinician message | Generic decision `notes` | Partial | Define patient-safe approved message contract |
| Approved recommendation snapshot | Absent | No | Versioned immutable approved snapshot |
| Common Advice | Generated/stored in mutable `results_review` | Partial | Govern inputs and copy approved output into snapshot |
| Patient result release | Guarded raw-evaluation RPC only | Partial | Patient-safe projection and explicit release authority |
| Revision safety | Case revision and decision check exist | Partial | Investigation revision and expected-revision evaluation/save contracts |

## R. Changes made during the audit

**DATABASE CHANGES:** none
**SOURCE CODE CHANGES:** none
**RLS CHANGES:** none
**DEPLOYMENTS:** none

This Markdown report is documentation only. The pre-existing Phase 1/2
working-tree modifications were not changed.

## S. Go / no-go

**PARTIAL GO — SOME LIVE AUTHORITY STILL UNRESOLVED**

The existing backend can be reused substantially, but implementation must not
begin for laboratory validation or Withhold behavior until authoritative units
and decision semantics are fixed.

## T. Next step

Approve a reconciled Phase 3 backend delta contract that explicitly defines the
Vitamin D/ionised-calcium units and exact Withhold semantics.
