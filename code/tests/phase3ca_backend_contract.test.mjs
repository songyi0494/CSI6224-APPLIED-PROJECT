import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const { PGlite } = await import(
  process.env.PGLITE_MODULE || '@electric-sql/pglite'
);

const patient = '10000000-0000-4000-8000-000000000001';
const patientMissingDob = '10000000-0000-4000-8000-000000000002';
const patientFutureDob = '10000000-0000-4000-8000-000000000003';
const patientBirthdayPending = '10000000-0000-4000-8000-000000000004';
const approved = '20000000-0000-4000-8000-000000000001';
const pending = '20000000-0000-4000-8000-000000000002';
const rejected = '20000000-0000-4000-8000-000000000003';
const otherClinician = '20000000-0000-4000-8000-000000000004';

const caseId = '40000000-0000-4000-8000-000000000001';
const noInvestigationCase = '40000000-0000-4000-8000-000000000002';
const staleCase = '40000000-0000-4000-8000-000000000003';
const adviceCase = '40000000-0000-4000-8000-000000000004';
const missingDobCase = '40000000-0000-4000-8000-000000000005';
const futureDobCase = '40000000-0000-4000-8000-000000000006';
const birthdayPendingCase = '40000000-0000-4000-8000-000000000007';
const pendingClaimCase = '40000000-0000-4000-8000-000000000008';
const rejectedClaimCase = '40000000-0000-4000-8000-000000000009';
const inaccessibleCase = '40000000-0000-4000-8000-000000000010';

const responseId = '50000000-0000-4000-8000-000000000001';
const migration = readFileSync(
  new URL(
    '../supabase/migrations/202609290001_phase3ca_security_investigations_gate_age_advice.sql',
    import.meta.url,
  ),
  'utf8',
);
const finalResultMigration = readFileSync(
  new URL(
    '../supabase/migrations/202609290002_final_result_contract.sql',
    import.meta.url,
  ),
  'utf8',
);
const repositorySource = readFileSync(
  new URL('../../app/lib/data/supabase_app_repository.dart', import.meta.url),
  'utf8',
);

function dartStringConstant(name) {
  const match = repositorySource.match(
    new RegExp(`static const ${name}\\s*=\\s*((?:'[^']*'\\s*)+);`),
  );
  assert.ok(match, `Missing Dart string constant ${name}`);
  return [...match[1].matchAll(/'([^']*)'/g)]
    .map((part) => part[1])
    .join('')
    .split(',')
    .map((column) => column.trim())
    .filter(Boolean);
}

function migrationClinicalCaseGrantColumns() {
  const match = migration.match(
    /grant select\s*\(([\s\S]*?)\)\s*on public\.clinical_cases to authenticated;/i,
  );
  assert.ok(match, 'Missing bounded clinical_cases SELECT grant');
  return match[1]
    .split(',')
    .map((column) => column.trim())
    .filter(Boolean);
}

const baseline = `
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on function auth.uid() to public;

create table public.profiles (
  id uuid primary key,
  role text not null,
  full_name text,
  date_of_birth date,
  gender text,
  approval_status text not null default 'approved'
);

create table public.questionnaire_responses (
  id uuid primary key,
  patient_id uuid not null references public.profiles(id),
  answers jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  revision integer not null default 1,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clinical_cases (
  id uuid primary key,
  patient_id uuid not null references public.profiles(id),
  assigned_clinician_id uuid references public.profiles(id),
  clinician_facts jsonb not null default '{}'::jsonb,
  pathway text,
  routing_reason text,
  status text not null default 'draft',
  submitted_at timestamptz,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  results_review jsonb not null default '{}'::jsonb,
  rule_evaluation jsonb,
  questionnaire_response_id uuid references public.questionnaire_responses(id),
  pathway_revision integer not null default 0,
  pathway_answer_order text[] not null default '{}'::text[]
);

create table public.investigations (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null unique references public.clinical_cases(id) on delete cascade,
  entered_by uuid not null references public.profiles(id),
  vitamin_d_level numeric check (vitamin_d_level is null or vitamin_d_level >= 0),
  total_calcium numeric,
  ionised_calcium numeric check (ionised_calcium is null or ionised_calcium >= 0),
  phosphate numeric,
  tsh numeric,
  body_weight_kg numeric check (body_weight_kg is null or body_weight_kg > 0),
  t_score numeric,
  test_date date,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clinician_decisions (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null unique references public.clinical_cases(id) on delete cascade,
  clinician_id uuid not null references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('approved', 'rejected')),
  notes text,
  pathway_revision integer not null check (pathway_revision >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function public.is_approved_clinician() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'clinician'
      and p.approval_status = 'approved'
  )
$$;

create function public.save_rule_evaluation(uuid, jsonb) returns void
language sql security definer set search_path = '' as $$ select $$;
create function public.review_clinical_case_results(uuid) returns void
language sql security definer set search_path = '' as $$ select $$;
create function public.review_pathway_evaluation(uuid, text, text default null) returns void
language sql security definer set search_path = '' as $$ select $$;

alter table public.profiles enable row level security;
alter table public.questionnaire_responses enable row level security;
alter table public.clinical_cases enable row level security;
alter table public.investigations enable row level security;

create policy profiles_own_read on public.profiles for select to authenticated
using (id = auth.uid());
create policy responses_owner_read on public.questionnaire_responses for select to authenticated
using (patient_id = auth.uid());
create policy cases_patient_read on public.clinical_cases for select to authenticated
using (patient_id = auth.uid());
create policy cases_clinician_read on public.clinical_cases for select to authenticated
using (
  assigned_clinician_id = auth.uid()
  or (assigned_clinician_id is null and status = 'clinician_input_required')
);
create policy investigations_clinician_read on public.investigations for select to authenticated
using (
  public.is_approved_clinician()
  and exists (
    select 1 from public.clinical_cases c
    where c.id = investigations.case_id
      and c.assigned_clinician_id = auth.uid()
  )
);
create policy investigations_clinician_write on public.investigations for all to authenticated
using (public.is_approved_clinician())
with check (public.is_approved_clinician());

grant select on public.profiles, public.questionnaire_responses to authenticated;
grant select (
  id, patient_id, assigned_clinician_id, pathway, routing_reason, status,
  submitted_at, claimed_at, created_at, updated_at, results_review,
  questionnaire_response_id, pathway_revision
) on public.clinical_cases to authenticated;
grant select, insert, update on public.investigations to authenticated;
grant execute on function public.is_approved_clinician() to authenticated;
`;

let db;

async function as(user, role = 'authenticated') {
  await db.exec(`
    reset role;
    select set_config('request.jwt.claim.sub', '${user}', false);
    set role ${role};
  `);
}

async function rpc(sql, params = []) {
  return (await db.query(sql, params)).rows[0]?.result;
}

async function seed() {
  await db.exec("reset role; select set_config('request.jwt.claim.sub','',false);");
  const profiles = [
    [patient, 'patient', 'Patient One', "current_date - interval '40 years 1 day'", 'female', 'approved'],
    [patientMissingDob, 'patient', 'No DOB', 'null', 'male', 'approved'],
    [patientFutureDob, 'patient', 'Future DOB', "current_date + interval '1 day'", 'another_term', 'approved'],
    [patientBirthdayPending, 'patient', 'Birthday Pending', "current_date - interval '40 years' + interval '1 day'", 'female', 'approved'],
    [approved, 'clinician', 'Approved Clinician', 'null', null, 'approved'],
    [pending, 'clinician', 'Pending Clinician', 'null', null, 'pending'],
    [rejected, 'clinician', 'Rejected Clinician', 'null', null, 'rejected'],
    [otherClinician, 'clinician', 'Other Clinician', 'null', null, 'approved'],
  ];
  for (const [id, role, name, dob, gender, approval] of profiles) {
    const genderSql = gender === null ? 'null' : `'${gender}'`;
    await db.exec(`insert into public.profiles(id,role,full_name,date_of_birth,gender,approval_status)
      values ('${id}','${role}','${name}',${dob},${genderSql},'${approval}')`);
  }

  await db.query(
    `insert into public.questionnaire_responses
      (id,patient_id,answers,status,revision,submitted_at)
     values ($1,$2,$3,'submitted',1,now())`,
    [responseId, patient, JSON.stringify({ dietaryDairyServings: 2 })],
  );

  const cases = [
    [caseId, patient, approved, 'in_progress', null],
    [noInvestigationCase, patient, approved, 'in_progress', null],
    [staleCase, patient, approved, 'in_progress', null],
    [adviceCase, patient, approved, 'in_progress', responseId],
    [missingDobCase, patientMissingDob, approved, 'in_progress', null],
    [futureDobCase, patientFutureDob, approved, 'in_progress', null],
    [birthdayPendingCase, patientBirthdayPending, approved, 'in_progress', null],
    [pendingClaimCase, patient, null, 'clinician_input_required', null],
    [rejectedClaimCase, patient, null, 'clinician_input_required', null],
    [inaccessibleCase, patient, otherClinician, 'in_progress', null],
  ];
  for (const row of cases) {
    await db.query(
      `insert into public.clinical_cases
        (id,patient_id,assigned_clinician_id,status,questionnaire_response_id)
       values ($1,$2,$3,$4,$5)`,
      row,
    );
  }
}

test('Songyi Phase 3C-A guarded backend contract', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'songyi-phase3ca-'));
  db = new PGlite(directory);
  try {
    await db.exec(baseline);
    await db.exec(migration);
    await seed();

    await t.test('clinical case columns and row scope stay bounded', async () => {
      const requiredColumns = new Set(
        dartStringConstant('clinicalCaseListSelectColumns'),
      );

      await as(approved);
      for (const column of requiredColumns) {
        await db.query(`select ${column} from public.clinical_cases limit 1`);
      }

      const visibleIds = (
        await db.query('select id from public.clinical_cases order by id')
      ).rows.map((row) => row.id);
      assert.ok(visibleIds.includes(caseId));
      assert.ok(visibleIds.includes(pendingClaimCase));
      assert.equal(visibleIds.includes(inaccessibleCase), false);

      await assert.rejects(
        db.query('select clinician_facts from public.clinical_cases limit 1'),
      );
      await assert.rejects(
        db.query('select results_review from public.clinical_cases limit 1'),
      );
      await assert.rejects(
        db.query('select rule_evaluation from public.clinical_cases limit 1'),
      );

      const detail = await rpc(
        'select public.get_clinical_case_detail($1) as result',
        [caseId],
      );
      assert.equal(detail.id, caseId);
      assert.equal(detail.patient_name, 'Patient One');
      assert.equal(detail.profile_sex_at_birth, 'female');
      assert.deepEqual(detail.clinician_facts, {});

      await assert.rejects(
        db.query('select public.get_clinical_case_detail($1)', [inaccessibleCase]),
      );
      await as(patient);
      await assert.rejects(
        db.query('select public.get_clinical_case_detail($1)', [caseId]),
      );
    });

    await t.test('claim requires an approved clinician', async () => {
      await as(pending);
      await assert.rejects(
        db.query('select public.claim_clinical_case($1)', [pendingClaimCase]),
      );
      await as(rejected);
      await assert.rejects(
        db.query('select public.claim_clinical_case($1)', [rejectedClaimCase]),
      );
      await as(approved);
      await db.query('select public.claim_clinical_case($1)', [pendingClaimCase]);
      const claimed = await rpc(
        'select assigned_clinician_id as result from public.clinical_cases where id=$1',
        [pendingClaimCase],
      );
      assert.equal(claimed, approved);
    });

    await t.test('guarded investigations save owns completion and revision', async () => {
      await as(approved);
      const empty = await rpc(
        'select public.get_case_investigations($1) as result',
        [caseId],
      );
      assert.equal(empty.revision, 0);
      assert.equal(empty.completed, false);

      await assert.rejects(
        db.query(
          'select public.save_case_investigations($1,$2,$3,$4,$5)',
          [caseId, null, 1.2, 70, 0],
        ),
      );

      const saved = await rpc(
        'select public.save_case_investigations($1,$2,$3,$4,$5) as result',
        [caseId, 55, 1.2, 70, 0],
      );
      assert.equal(saved.completed, true);
      assert.equal(saved.revision, 1);
      assert.equal(saved.vitaminD.unit, 'nmol/L');
      assert.equal(saved.ionisedCalcium.unit, 'mmol/L');
      assert.equal(saved.bodyWeight.unit, 'kg');

      await assert.rejects(
        db.query(
          'select public.save_case_investigations($1,$2,$3,$4,$5)',
          [caseId, 56, 1.21, 71, 0],
        ),
      );

      await as(otherClinician);
      await assert.rejects(
        db.query(
          'select public.save_case_investigations($1,$2,$3,$4,$5)',
          [caseId, 56, 1.21, 71, 1],
        ),
      );

      await as(approved);
      await assert.rejects(
        db.query(
          'update public.investigations set completed_at=now() where case_id=$1',
          [caseId],
        ),
      );
    });

    await t.test('pathway boundaries reject incomplete and stale investigations', async () => {
      const evaluation = JSON.stringify({
        status: 'complete',
        pathwayId: 'PATHWAY1',
        actions: [],
        trace: [],
      });
      await as(approved);
      await assert.rejects(
        db.query('select public.get_pathway_case_context($1)', [noInvestigationCase]),
      );
      await assert.rejects(
        db.query('select public.save_pathway_answer($1,$2,$3)', [
          noInvestigationCase,
          'eGFR',
          JSON.stringify(55),
        ]),
      );
      await assert.rejects(
        db.query('select public.save_rule_evaluation($1,$2,$3,$4)', [
          noInvestigationCase,
          evaluation,
          0,
          0,
        ]),
      );

      await rpc(
        'select public.save_case_investigations($1,$2,$3,$4,$5) as result',
        [staleCase, 55, 1.2, 70, 0],
      );
      const context = await rpc(
        'select public.get_pathway_case_context($1) as result',
        [staleCase],
      );
      assert.equal(context.pathway_revision, 0);
      assert.equal(context.investigation_revision, 1);

      await rpc(
        'select public.save_case_investigations($1,$2,$3,$4,$5) as result',
        [staleCase, 56, 1.21, 71, 1],
      );
      await assert.rejects(
        db.query('select public.save_rule_evaluation($1,$2,$3,$4)', [
          staleCase,
          evaluation,
          context.pathway_revision,
          context.investigation_revision,
        ]),
      );

      await db.query('select public.save_pathway_answer($1,$2,$3)', [
        staleCase,
        'eGFR',
        JSON.stringify(55),
      ]);
      const current = await rpc(
        'select public.get_pathway_case_context($1) as result',
        [staleCase],
      );
      await db.query('select public.save_rule_evaluation($1,$2,$3,$4)', [
        staleCase,
        evaluation,
        current.pathway_revision,
        current.investigation_revision,
      ]);
      await db.exec('reset role');
      const stored = await rpc(
        "select rule_evaluation->>'investigationRevision' as result from public.clinical_cases where id=$1",
        [staleCase],
      );
      assert.equal(Number(stored), 2);
    });

    await t.test('age projection uses completed age and hides DOB', async () => {
      await as(approved);
      const occurred = await rpc(
        'select public.get_clinical_case_patient_summary($1) as result',
        [caseId],
      );
      assert.equal(occurred.age, 40);
      assert.equal(occurred.patientDisplayName, 'Patient One');
      assert.ok(occurred.ageAsOf);
      assert.equal('dateOfBirth' in occurred, false);

      const pendingBirthday = await rpc(
        'select public.get_clinical_case_patient_summary($1) as result',
        [birthdayPendingCase],
      );
      assert.equal(pendingBirthday.age, 39);

      const missing = await rpc(
        'select public.get_clinical_case_patient_summary($1) as result',
        [missingDobCase],
      );
      const future = await rpc(
        'select public.get_clinical_case_patient_summary($1) as result',
        [futureDobCase],
      );
      assert.equal(missing.age, null);
      assert.equal(future.age, null);

      await assert.rejects(
        db.query('select public.get_clinical_case_patient_summary($1)', [
          inaccessibleCase,
        ]),
      );
    });

    await t.test('Common Advice is current, revision-bound and clinician-only', async () => {
      await as(approved);
      await assert.rejects(
        db.query('select public.review_clinical_case_results($1,$2,$3)', [
          adviceCase,
          0,
          1,
        ]),
      );

      await rpc(
        'select public.save_case_investigations($1,$2,$3,$4,$5) as result',
        [adviceCase, 35, 1.1, 70, 0],
      );
      const candidate = await rpc(
        'select public.review_clinical_case_results($1,$2,$3) as result',
        [adviceCase, 1, 1],
      );
      assert.equal(candidate.vitaminD.unit, 'nmol/L');
      assert.equal(candidate.calcium.ionisedCalciumUnit, 'mmol/L');
      assert.equal(candidate.protein.bodyWeightUnit, 'kg');
      assert.equal(candidate.source.investigationRevision, 1);
      assert.equal(candidate.source.questionnaireRevision, 1);

      const clinicianRead = await rpc(
        'select public.get_clinical_case_results_review($1) as result',
        [adviceCase],
      );
      assert.deepEqual(clinicianRead, candidate);

      await as(patient);
      await assert.rejects(
        db.query('select results_review from public.clinical_cases where id=$1', [
          adviceCase,
        ]),
      );
      await assert.rejects(
        db.query('select public.get_clinical_case_results_review($1)', [adviceCase]),
      );

      await as(approved);
      await rpc(
        'select public.save_case_investigations($1,$2,$3,$4,$5) as result',
        [adviceCase, 36, 1.11, 71, 1],
      );
      await assert.rejects(
        db.query('select public.get_clinical_case_results_review($1)', [adviceCase]),
      );
    });

    await t.test('final result migration applies on the Phase 3C-A live shape', async () => {
      await db.exec('reset role');
      await db.exec(finalResultMigration);

      const columns = (
        await db.query(`
          select column_name
          from information_schema.columns
          where table_schema='public'
            and table_name='clinician_decisions'
        `)
      ).rows.map((row) => row.column_name);
      assert.ok(columns.includes('approved_actions_snapshot'));
      assert.ok(columns.includes('approved_common_advice_snapshot'));
      assert.ok(columns.includes('released_at'));

      const definition = (
        await db.query(`
          select pg_get_functiondef(p.oid) as definition
          from pg_proc p
          join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public'
            and p.proname='get_patient_approved_results'
        `)
      ).rows[0].definition;
      assert.match(definition, /d\.decision = 'approved'/);
      assert.match(definition, /d\.released_at IS NOT NULL/i);

      await db.exec(`
        update public.clinical_cases
        set status='evaluated',
            pathway='PATHWAY1',
            pathway_revision=1,
            rule_evaluation=jsonb_build_object(
              'status','complete',
              'pathwayId','PATHWAY1',
              'pathwayRevision',1,
              'investigationRevision',2,
              'actions',jsonb_build_array(
                jsonb_build_object('type','recommendation','recommendation','Approved action')
              ),
              'trace','[]'::jsonb
            )
        where id='${adviceCase}'
      `);
      await as(approved);
      await rpc(
        'select public.review_clinical_case_results($1,$2,$3) as result',
        [adviceCase, 2, 1],
      );
      await db.query(
        'select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',
        [adviceCase, 'approved', 'Approved patient message', 1, 2, 1],
      );

      await as(patient);
      const released = await rpc(
        'select public.get_patient_approved_results() as result',
      );
      assert.equal(released.length, 1);
      assert.deepEqual(Object.keys(released[0]).sort(), [
        'careRecommendation',
        'caseId',
        'clinicianMessage',
        'lifestyleRecommendations',
        'reviewedAt',
      ]);
      assert.equal(released[0].clinicianMessage, 'Approved patient message');

      await as(approved);
      await db.query(
        'select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',
        [adviceCase, 'withheld', null, 1, 2, null],
      );
      await as(patient);
      assert.deepEqual(
        await rpc('select public.get_patient_approved_results() as result'),
        [],
      );
    });
  } finally {
    await db.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('tracked deployed evaluator source binds both server revisions', () => {
  const evaluatorSource = readFileSync(
    new URL(
      '../supabase/functions/evaluate_pathway/index.ts',
      import.meta.url,
    ),
    'utf8',
  );
  assert.match(evaluatorSource, /investigation_revision: number/);
  assert.match(evaluatorSource, /p_expected_pathway_revision/);
  assert.match(evaluatorSource, /p_expected_investigation_revision/);
  assert.doesNotMatch(evaluatorSource, /withheld|Withhold/);
});

test('Flutter Work Queue select matches grant and case detail stays guarded', () => {
  const listColumns = dartStringConstant('clinicalCaseListSelectColumns');
  const grantedColumns = migrationClinicalCaseGrantColumns().sort();

  assert.deepEqual(grantedColumns, [...listColumns].sort());
  assert.deepEqual(listColumns, [
    'id',
    'patient_id',
    'status',
    'submitted_at',
    'updated_at',
  ]);
  assert.match(repositorySource, /clinicalCaseDetailRpc\s*=\s*'get_clinical_case_detail'/);
  assert.match(migration, /create or replace function public\.get_clinical_case_detail/);
  assert.equal(grantedColumns.includes('clinician_facts'), false);
  assert.equal(grantedColumns.includes('results_review'), false);
  assert.equal(grantedColumns.includes('rule_evaluation'), false);
  assert.match(
    migration,
    /revoke select \(clinician_facts, results_review, rule_evaluation\)/,
  );
});
