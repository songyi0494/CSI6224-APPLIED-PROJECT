begin;

-- Phase 3C-A is an additive delta against the verified Songyi live schema.
-- Stop rather than create parallel structures when the live prerequisites differ.
do $$
declare
  missing text[];
begin
  select array_agg(required.name order by required.name)
  into missing
  from (values
    ('clinical_cases'),
    ('investigations'),
    ('profiles'),
    ('questionnaire_responses')
  ) as required(name)
  where to_regclass('public.' || required.name) is null;

  if missing is not null then
    raise exception 'Phase 3C-A live prerequisites are missing: %', missing;
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_approved_clinician'
  ) then
    raise exception 'Phase 3C-A requires public.is_approved_clinician()';
  end if;
end $$;

alter table public.investigations
  add column if not exists revision integer not null default 0
  check (revision >= 0);

comment on column public.investigations.vitamin_d_level is
  'Songyi Phase 3B authority: Vitamin D level in nmol/L.';
comment on column public.investigations.ionised_calcium is
  'Songyi Phase 3B authority: ionised calcium level in mmol/L.';
comment on column public.investigations.body_weight_kg is
  'Songyi Phase 3B authority: body weight in kg.';
comment on column public.investigations.revision is
  'Server-controlled optimistic concurrency revision. Revision 0 is legacy/unreviewed and is not complete.';

create or replace function public.phase3ca_investigations_complete(
  p_case_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.investigations i
    where i.case_id = p_case_id
      and i.revision > 0
      and i.completed_at is not null
      and i.vitamin_d_level is not null
      and i.vitamin_d_level >= 0
      and i.vitamin_d_level::text not in ('NaN', 'Infinity', '-Infinity')
      and i.ionised_calcium is not null
      and i.ionised_calcium >= 0
      and i.ionised_calcium::text not in ('NaN', 'Infinity', '-Infinity')
      and i.body_weight_kg is not null
      and i.body_weight_kg > 0
      and i.body_weight_kg::text not in ('NaN', 'Infinity', '-Infinity')
  );
$$;

revoke all on function public.phase3ca_investigations_complete(uuid)
from public, anon, authenticated;

create or replace function public.claim_clinical_case(
  p_case_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can claim clinical cases'
      using errcode = '42501';
  end if;

  update public.clinical_cases
  set assigned_clinician_id = auth.uid(),
      status = 'in_progress',
      claimed_at = now(),
      updated_at = now()
  where id = p_case_id
    and status = 'clinician_input_required'
    and assigned_clinician_id is null;

  if not found then
    raise exception 'Clinical case is not available for claim';
  end if;
end;
$$;

create or replace function public.save_case_investigations(
  p_case_id uuid,
  p_vitamin_d_level numeric,
  p_ionised_calcium numeric,
  p_body_weight_kg numeric,
  p_expected_revision integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation public.investigations%rowtype;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can save investigations'
      using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Expected investigation revision is required';
  end if;

  if p_vitamin_d_level is null
    or p_vitamin_d_level < 0
    or p_vitamin_d_level::text in ('NaN', 'Infinity', '-Infinity')
  then
    raise exception 'Vitamin D must be a finite non-negative value in nmol/L';
  end if;

  if p_ionised_calcium is null
    or p_ionised_calcium < 0
    or p_ionised_calcium::text in ('NaN', 'Infinity', '-Infinity')
  then
    raise exception 'Ionised calcium must be a finite non-negative value in mmol/L';
  end if;

  if p_body_weight_kg is null
    or p_body_weight_kg <= 0
    or p_body_weight_kg::text in ('NaN', 'Infinity', '-Infinity')
  then
    raise exception 'Body weight must be a finite positive value in kg';
  end if;

  select *
  into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then
    raise exception 'Clinical case not found';
  end if;

  if v_case.assigned_clinician_id is distinct from auth.uid()
    or v_case.status <> 'in_progress'
  then
    raise exception 'You can only save investigations for your assigned in-progress case'
      using errcode = '42501';
  end if;

  select *
  into v_investigation
  from public.investigations
  where case_id = p_case_id
  for update;

  if found then
    if v_investigation.revision is distinct from p_expected_revision then
      raise exception 'Investigations changed. Reload before saving';
    end if;

    update public.investigations
    set vitamin_d_level = p_vitamin_d_level,
        ionised_calcium = p_ionised_calcium,
        body_weight_kg = p_body_weight_kg,
        entered_by = auth.uid(),
        revision = revision + 1,
        completed_at = now(),
        updated_at = now()
    where case_id = p_case_id
    returning * into v_investigation;
  else
    if p_expected_revision <> 0 then
      raise exception 'Investigations changed. Reload before saving';
    end if;

    insert into public.investigations (
      case_id,
      entered_by,
      vitamin_d_level,
      ionised_calcium,
      body_weight_kg,
      revision,
      completed_at
    ) values (
      p_case_id,
      auth.uid(),
      p_vitamin_d_level,
      p_ionised_calcium,
      p_body_weight_kg,
      1,
      now()
    )
    returning * into v_investigation;
  end if;

  -- This is derived clinician-side candidate output. Preserve pathway answers,
  -- but require the candidate to be regenerated from the new investigation revision.
  update public.clinical_cases
  set results_review = '{}'::jsonb,
      updated_at = now()
  where id = p_case_id;

  return jsonb_build_object(
    'caseId', v_investigation.case_id,
    'vitaminD', jsonb_build_object(
      'value', v_investigation.vitamin_d_level,
      'unit', 'nmol/L'
    ),
    'ionisedCalcium', jsonb_build_object(
      'value', v_investigation.ionised_calcium,
      'unit', 'mmol/L'
    ),
    'bodyWeight', jsonb_build_object(
      'value', v_investigation.body_weight_kg,
      'unit', 'kg'
    ),
    'revision', v_investigation.revision,
    'completed', public.phase3ca_investigations_complete(p_case_id),
    'completedAt', v_investigation.completed_at,
    'updatedAt', v_investigation.updated_at
  );
end;
$$;

create or replace function public.get_case_investigations(
  p_case_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation public.investigations%rowtype;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read investigations'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found or v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'Clinical case is not available'
      using errcode = '42501';
  end if;

  select * into v_investigation
  from public.investigations
  where case_id = p_case_id;

  if not found then
    return jsonb_build_object(
      'caseId', p_case_id,
      'vitaminD', jsonb_build_object('value', null, 'unit', 'nmol/L'),
      'ionisedCalcium', jsonb_build_object('value', null, 'unit', 'mmol/L'),
      'bodyWeight', jsonb_build_object('value', null, 'unit', 'kg'),
      'revision', 0,
      'completed', false,
      'completedAt', null,
      'updatedAt', null
    );
  end if;

  return jsonb_build_object(
    'caseId', v_investigation.case_id,
    'vitaminD', jsonb_build_object(
      'value', v_investigation.vitamin_d_level,
      'unit', 'nmol/L'
    ),
    'ionisedCalcium', jsonb_build_object(
      'value', v_investigation.ionised_calcium,
      'unit', 'mmol/L'
    ),
    'bodyWeight', jsonb_build_object(
      'value', v_investigation.body_weight_kg,
      'unit', 'kg'
    ),
    'revision', v_investigation.revision,
    'completed', public.phase3ca_investigations_complete(p_case_id),
    'completedAt', v_investigation.completed_at,
    'updatedAt', v_investigation.updated_at
  );
end;
$$;

create or replace function public.get_clinical_case_patient_summary(
  p_case_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_name text;
  v_date_of_birth date;
  v_age integer;
  v_as_of date := current_date;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read patient summaries'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found
    or not (
      v_case.assigned_clinician_id = auth.uid()
      or (
        v_case.assigned_clinician_id is null
        and v_case.status = 'clinician_input_required'
      )
    )
  then
    raise exception 'Clinical case is not available'
      using errcode = '42501';
  end if;

  select full_name, date_of_birth
  into v_name, v_date_of_birth
  from public.profiles
  where id = v_case.patient_id;

  if v_date_of_birth is null or v_date_of_birth > v_as_of then
    v_age := null;
  else
    v_age := extract(year from age(v_as_of, v_date_of_birth))::integer;
  end if;

  return jsonb_build_object(
    'caseId', v_case.id,
    'patientDisplayName', v_name,
    'age', v_age,
    'ageAsOf', v_as_of
  );
end;
$$;

-- Case detail is clinician-only because clinician_facts must not be granted to
-- every authenticated user (patients and clinicians share that database role).
-- This preserves the existing clinician row scope while returning only the
-- fields consumed by the current Patient Overview/pathway screens.
create or replace function public.get_clinical_case_detail(
  p_case_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_patient_name text;
  v_profile_gender text;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read clinical case detail'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found
    or not (
      v_case.assigned_clinician_id = auth.uid()
      or (
        v_case.assigned_clinician_id is null
        and v_case.status = 'clinician_input_required'
      )
    )
  then
    raise exception 'Clinical case is not available'
      using errcode = '42501';
  end if;

  select full_name, gender
  into v_patient_name, v_profile_gender
  from public.profiles
  where id = v_case.patient_id;

  return jsonb_build_object(
    'id', v_case.id,
    'patient_id', v_case.patient_id,
    'patient_name', v_patient_name,
    'profile_sex_at_birth', v_profile_gender,
    'clinician_facts', v_case.clinician_facts,
    'pathway', v_case.pathway,
    'routing_reason', v_case.routing_reason,
    'status', v_case.status,
    'submitted_at', v_case.submitted_at,
    'updated_at', v_case.updated_at
  );
end;
$$;

create or replace function public.get_pathway_case_context(
  p_case_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation_revision integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can evaluate pathways'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found then
    raise exception 'Clinical case not found';
  end if;

  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only evaluate your assigned clinical case'
      using errcode = '42501';
  end if;

  if v_case.status <> 'in_progress' then
    raise exception 'Only in-progress clinical cases can be evaluated';
  end if;

  if not public.phase3ca_investigations_complete(p_case_id) then
    raise exception 'Current complete investigations are required before evaluating the pathway';
  end if;

  select revision into v_investigation_revision
  from public.investigations
  where case_id = p_case_id;

  return jsonb_build_object(
    'id', v_case.id,
    'clinician_facts', v_case.clinician_facts,
    'pathway_answer_order', v_case.pathway_answer_order,
    'assigned_clinician_id', v_case.assigned_clinician_id,
    'status', v_case.status,
    'pathway_revision', v_case.pathway_revision,
    'investigation_revision', v_investigation_revision
  );
end;
$$;

create or replace function public.save_pathway_answer(
  p_case_id uuid,
  p_field_key text,
  p_value jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_updated_facts jsonb;
  v_updated_order text[];
  v_existing_position integer;
  v_downstream_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can save pathway answers'
      using errcode = '42501';
  end if;

  if p_field_key is null or btrim(p_field_key) = '' then
    raise exception 'Pathway answer field key is required';
  end if;

  if p_value is null or p_value = 'null'::jsonb then
    raise exception 'Pathway answer value is required';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then
    raise exception 'Clinical case not found';
  end if;

  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only update your assigned clinical case'
      using errcode = '42501';
  end if;

  if v_case.status <> 'in_progress' then
    raise exception 'Only in-progress clinical cases can receive pathway answers';
  end if;

  if not public.phase3ca_investigations_complete(p_case_id) then
    raise exception 'Current complete investigations are required before starting the pathway';
  end if;

  v_updated_facts := coalesce(v_case.clinician_facts, '{}'::jsonb);
  v_updated_order := coalesce(v_case.pathway_answer_order, '{}'::text[]);
  v_existing_position := array_position(v_updated_order, p_field_key);

  if v_existing_position is not null
    and v_updated_facts -> p_field_key = p_value
  then
    return v_updated_facts;
  end if;

  if cardinality(v_updated_order) = 0 then
    v_updated_facts := '{}'::jsonb;
    v_updated_order := array[p_field_key];
  elsif v_existing_position is not null then
    if v_existing_position < cardinality(v_updated_order) then
      foreach v_downstream_key in array
        v_updated_order[(v_existing_position + 1):cardinality(v_updated_order)]
      loop
        v_updated_facts := v_updated_facts - v_downstream_key;
      end loop;
    end if;
    v_updated_order := v_updated_order[1:v_existing_position];
  else
    v_updated_order := array_append(v_updated_order, p_field_key);
  end if;

  v_updated_facts := jsonb_set(
    v_updated_facts,
    array[p_field_key],
    p_value,
    true
  );

  update public.clinical_cases
  set clinician_facts = v_updated_facts,
      pathway_answer_order = v_updated_order,
      pathway_revision = pathway_revision + 1,
      rule_evaluation = null,
      pathway = null,
      routing_reason = null,
      updated_at = now()
  where id = p_case_id
  returning clinician_facts into v_updated_facts;

  return v_updated_facts;
end;
$$;

revoke all on function public.save_rule_evaluation(uuid, jsonb)
from public, anon, authenticated;
drop function public.save_rule_evaluation(uuid, jsonb);

create function public.save_rule_evaluation(
  p_case_id uuid,
  p_evaluation jsonb,
  p_expected_pathway_revision integer,
  p_expected_investigation_revision integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation public.investigations%rowtype;
  v_pathway text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can save pathway evaluations'
      using errcode = '42501';
  end if;

  if p_expected_pathway_revision is null
    or p_expected_investigation_revision is null
  then
    raise exception 'Expected pathway and investigation revisions are required';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then
    raise exception 'Clinical case not found';
  end if;

  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only evaluate your assigned clinical case'
      using errcode = '42501';
  end if;

  if v_case.status <> 'in_progress' then
    raise exception 'Only in-progress clinical cases can be evaluated';
  end if;

  if v_case.pathway_revision is distinct from p_expected_pathway_revision then
    raise exception 'Pathway answers changed. Reload before saving the evaluation';
  end if;

  select * into v_investigation
  from public.investigations
  where case_id = p_case_id
  for update;

  if not found
    or v_investigation.revision is distinct from p_expected_investigation_revision
    or not public.phase3ca_investigations_complete(p_case_id)
  then
    raise exception 'Investigations changed or are incomplete. Re-evaluate before saving';
  end if;

  if (p_evaluation ->> 'status') is distinct from 'complete' then
    raise exception 'Only completed pathway evaluations can be saved';
  end if;

  v_pathway := p_evaluation ->> 'pathwayId';
  if v_pathway is null or v_pathway not in ('PATHWAY1', 'PATHWAY2') then
    raise exception 'Invalid pathway evaluation result';
  end if;

  if jsonb_typeof(p_evaluation -> 'actions') is distinct from 'array' then
    raise exception 'Evaluation actions must be an array';
  end if;

  if jsonb_typeof(p_evaluation -> 'trace') is distinct from 'array' then
    raise exception 'Evaluation trace must be an array';
  end if;

  update public.clinical_cases
  set rule_evaluation = p_evaluation || jsonb_build_object(
        'pathwayRevision', v_case.pathway_revision,
        'investigationRevision', v_investigation.revision,
        'savedAt', now()
      ),
      pathway = v_pathway,
      routing_reason = coalesce(
        routing_reason,
        'Final pathway determined by rule engine'
      ),
      status = 'evaluated',
      updated_at = now()
  where id = p_case_id;
end;
$$;

revoke all on function public.review_clinical_case_results(uuid)
from public, anon, authenticated;
drop function public.review_clinical_case_results(uuid);

create function public.review_clinical_case_results(
  p_case_id uuid,
  p_expected_investigation_revision integer,
  p_expected_questionnaire_revision integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation public.investigations%rowtype;
  v_date_of_birth date;
  v_answers jsonb;
  v_questionnaire_revision integer;
  v_questionnaire_status text;
  v_dietary_dairy_servings numeric;
  v_age integer;
  v_older_people boolean;
  v_vitamin_d_recommendation text;
  v_vitamin_d_recheck boolean;
  v_hypocalcaemia boolean;
  v_calcium_supplement_required boolean;
  v_calcium_recommendation text;
  v_protein_min_grams numeric;
  v_protein_max_grams numeric;
  v_protein_recommendation text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can review clinical case results'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then
    raise exception 'Clinical case not found';
  end if;

  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only review your assigned clinical case'
      using errcode = '42501';
  end if;

  if v_case.status <> 'in_progress' then
    raise exception 'Only in-progress clinical cases can be reviewed';
  end if;

  select answers, revision, status
  into v_answers, v_questionnaire_revision, v_questionnaire_status
  from public.questionnaire_responses
  where id = v_case.questionnaire_response_id;

  if not found or v_questionnaire_status <> 'submitted' then
    raise exception 'A submitted questionnaire response is required';
  end if;

  if v_questionnaire_revision is distinct from p_expected_questionnaire_revision then
    raise exception 'Questionnaire response changed. Reload before generating advice';
  end if;

  select * into v_investigation
  from public.investigations
  where case_id = p_case_id
  for update;

  if not found
    or v_investigation.revision is distinct from p_expected_investigation_revision
    or not public.phase3ca_investigations_complete(p_case_id)
  then
    raise exception 'Current complete investigations are required for results review';
  end if;

  select date_of_birth into v_date_of_birth
  from public.profiles
  where id = v_case.patient_id;

  if v_date_of_birth is null or v_date_of_birth > current_date then
    raise exception 'A valid patient date of birth is required for results review';
  end if;

  begin
    v_dietary_dairy_servings := nullif(
      v_answers ->> 'dietaryDairyServings',
      ''
    )::numeric;
  exception when others then
    raise exception 'Dietary dairy servings is invalid for results review';
  end;

  if v_dietary_dairy_servings is null
    or v_dietary_dairy_servings < 0
    or v_dietary_dairy_servings::text in ('NaN', 'Infinity', '-Infinity')
  then
    raise exception 'Dietary dairy servings is required for results review';
  end if;

  v_age := extract(year from age(current_date, v_date_of_birth))::integer;
  v_older_people := v_age >= 65;

  if v_investigation.vitamin_d_level < 40 then
    v_vitamin_d_recommendation :=
      'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily';
    v_vitamin_d_recheck := v_investigation.vitamin_d_level < 25;
  elsif v_investigation.vitamin_d_level between 40 and 75 then
    v_vitamin_d_recommendation :=
      'Cholecalciferol 25 microg daily ongoing';
    v_vitamin_d_recheck := false;
  else
    v_vitamin_d_recommendation := null;
    v_vitamin_d_recheck := false;
  end if;

  v_hypocalcaemia := v_investigation.ionised_calcium < 1.12;
  v_calcium_supplement_required :=
    v_dietary_dairy_servings < 3 or v_hypocalcaemia;

  if v_calcium_supplement_required then
    v_calcium_recommendation := 'Calcium supplement 600 mg daily';
  else
    v_calcium_recommendation := null;
  end if;

  if v_older_people then
    v_protein_min_grams := v_investigation.body_weight_kg * 1.0;
    v_protein_max_grams := v_investigation.body_weight_kg * 1.2;
    v_protein_recommendation :=
      'Protein target: 1.0-1.2 g/kg bodyweight daily';
  else
    v_protein_min_grams := null;
    v_protein_max_grams := null;
    v_protein_recommendation := null;
  end if;

  v_result := jsonb_build_object(
    'vitaminD', jsonb_build_object(
      'level', v_investigation.vitamin_d_level,
      'unit', 'nmol/L',
      'recommendation', v_vitamin_d_recommendation,
      'recheckBeforeTreatment', v_vitamin_d_recheck
    ),
    'calcium', jsonb_build_object(
      'totalCalcium', v_investigation.total_calcium,
      'ionisedCalcium', v_investigation.ionised_calcium,
      'ionisedCalciumUnit', 'mmol/L',
      'hypocalcaemia', v_hypocalcaemia,
      'supplementRequired', v_calcium_supplement_required,
      'recommendation', v_calcium_recommendation
    ),
    'protein', jsonb_build_object(
      'age', v_age,
      'ageAsOf', current_date,
      'olderPeople', v_older_people,
      'bodyWeightKg', v_investigation.body_weight_kg,
      'bodyWeightUnit', 'kg',
      'minimumGramsPerDay', v_protein_min_grams,
      'maximumGramsPerDay', v_protein_max_grams,
      'recommendation', v_protein_recommendation
    ),
    'lifestyleAdvice', jsonb_build_array(
      'Ceasing smoking',
      'Reducing alcohol intake',
      'Weight bearing exercises'
    ),
    'source', jsonb_build_object(
      'investigationRevision', v_investigation.revision,
      'questionnaireRevision', v_questionnaire_revision,
      'generatedAt', now(),
      'generatedBy', auth.uid()
    )
  );

  update public.clinical_cases
  set results_review = v_result,
      updated_at = now()
  where id = p_case_id;

  return v_result;
end;
$$;

create or replace function public.get_clinical_case_results_review(
  p_case_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation_revision integer;
  v_questionnaire_revision integer;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read candidate results review'
      using errcode = '42501';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found or v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'Clinical case is not available'
      using errcode = '42501';
  end if;

  if v_case.results_review = '{}'::jsonb
    or not public.phase3ca_investigations_complete(p_case_id)
  then
    raise exception 'Current candidate results review is not available';
  end if;

  select revision into v_investigation_revision
  from public.investigations
  where case_id = p_case_id;

  select revision into v_questionnaire_revision
  from public.questionnaire_responses
  where id = v_case.questionnaire_response_id
    and status = 'submitted';

  if (v_case.results_review #>> '{source,investigationRevision}')::integer
      is distinct from v_investigation_revision
    or (v_case.results_review #>> '{source,questionnaireRevision}')::integer
      is distinct from v_questionnaire_revision
  then
    raise exception 'Candidate results review is stale and must be regenerated';
  end if;

  return v_case.results_review;
end;
$$;

-- Keep direct clinical-case reads aligned with the bounded Work Queue contract.
-- Case detail, including clinician_facts, is available only through the guarded
-- get_clinical_case_detail RPC because patients share the authenticated role.
grant select (
  id,
  patient_id,
  status,
  submitted_at,
  updated_at
) on public.clinical_cases to authenticated;

-- Patients must not read pre-approval candidate results through the Data API.
revoke select (clinician_facts, results_review, rule_evaluation)
on public.clinical_cases from authenticated;

-- Direct clients may read only the bounded investigation fields. All writes,
-- including completed_at, entered_by and revision, go through the guarded RPC.
revoke select, insert, update, delete on public.investigations from authenticated;
grant select (
  case_id,
  vitamin_d_level,
  ionised_calcium,
  body_weight_kg,
  revision,
  completed_at,
  updated_at
) on public.investigations to authenticated;

revoke all on function
  public.claim_clinical_case(uuid),
  public.save_case_investigations(uuid, numeric, numeric, numeric, integer),
  public.get_case_investigations(uuid),
  public.get_clinical_case_patient_summary(uuid),
  public.get_clinical_case_detail(uuid),
  public.get_pathway_case_context(uuid),
  public.save_pathway_answer(uuid, text, jsonb),
  public.save_rule_evaluation(uuid, jsonb, integer, integer),
  public.review_clinical_case_results(uuid, integer, integer),
  public.get_clinical_case_results_review(uuid)
from public, anon, authenticated;

grant execute on function
  public.claim_clinical_case(uuid),
  public.save_case_investigations(uuid, numeric, numeric, numeric, integer),
  public.get_case_investigations(uuid),
  public.get_clinical_case_patient_summary(uuid),
  public.get_clinical_case_detail(uuid),
  public.get_pathway_case_context(uuid),
  public.save_pathway_answer(uuid, text, jsonb),
  public.save_rule_evaluation(uuid, jsonb, integer, integer),
  public.review_clinical_case_results(uuid, integer, integer),
  public.get_clinical_case_results_review(uuid)
to authenticated;

commit;
