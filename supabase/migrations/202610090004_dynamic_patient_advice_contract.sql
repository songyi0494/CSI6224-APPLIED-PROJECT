begin;
-- Forward-only advice/input contract. No historical answers or reviews are rewritten.
alter table public.investigations
  add column if not exists authoritative_hypocalcaemia boolean,
  add column if not exists hypocalcaemia_revision integer not null default 0 check (hypocalcaemia_revision >= 0);
comment on column public.investigations.authoritative_hypocalcaemia is
  'Clinician-confirmed hypocalcaemia. Null is unconfirmed. Never derived from ionised calcium.';
insert into public.questionnaire_questions(question_text,question_type,is_required,display_order,field_key,options)
values ('Do you have fewer than 3 serves of dairy per day?','checkbox',true,54,'dairyLessThan3Serves',null)
on conflict (field_key) do nothing;
do $$begin
  if exists(select 1 from public.questionnaire_questions where field_key='dairyLessThan3Serves'
    and (question_type is distinct from 'checkbox' or question_text is distinct from 'Do you have fewer than 3 serves of dairy per day?')) then
    raise exception 'The dairy threshold key conflicts with an existing questionnaire definition';
  end if;
end;$$;


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
      and (i.vitamin_d_level is null or (
      i.vitamin_d_level >= 0
      and i.vitamin_d_level::text not in ('NaN', 'Infinity', '-Infinity')))
      and (i.ionised_calcium is null or (
      i.ionised_calcium >= 0
      and i.ionised_calcium::text not in ('NaN', 'Infinity', '-Infinity')))
      and (i.body_weight_kg is null or (
      i.body_weight_kg > 0
      and i.body_weight_kg::text not in ('NaN', 'Infinity', '-Infinity')))
  );
$$;

create or replace function public.save_case_investigations(
  p_case_id uuid,
  p_vitamin_d_level numeric,
  p_ionised_calcium numeric,
  p_body_weight_kg numeric,
  p_expected_revision integer,
  p_authoritative_hypocalcaemia boolean
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

  if p_vitamin_d_level is not null and (
    p_vitamin_d_level < 0
    or p_vitamin_d_level::text in ('NaN', 'Infinity', '-Infinity'))
  then
    raise exception 'Vitamin D must be a finite non-negative value in nmol/L';
  end if;

  if p_ionised_calcium is not null and (
    p_ionised_calcium < 0
    or p_ionised_calcium::text in ('NaN', 'Infinity', '-Infinity'))
  then
    raise exception 'Ionised calcium must be a finite non-negative value in mmol/L';
  end if;

  if p_body_weight_kg is not null and (
    p_body_weight_kg <= 0
    or p_body_weight_kg::text in ('NaN', 'Infinity', '-Infinity'))
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
        authoritative_hypocalcaemia = coalesce(p_authoritative_hypocalcaemia, authoritative_hypocalcaemia),
        hypocalcaemia_revision = hypocalcaemia_revision + case
          when p_authoritative_hypocalcaemia is not null
            and (authoritative_hypocalcaemia is distinct from p_authoritative_hypocalcaemia or hypocalcaemia_revision=0) then 1 else 0 end,
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
      authoritative_hypocalcaemia,
      hypocalcaemia_revision,
      revision,
      completed_at
    ) values (
      p_case_id,
      auth.uid(),
      p_vitamin_d_level,
      p_ionised_calcium,
      p_body_weight_kg,
      p_authoritative_hypocalcaemia,
      case when p_authoritative_hypocalcaemia is null then 0 else 1 end,
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
    'authoritativeHypocalcaemia', v_investigation.authoritative_hypocalcaemia,
    'hypocalcaemiaRevision', v_investigation.hypocalcaemia_revision,
    'revision', v_investigation.revision,
    'completed', public.phase3ca_investigations_complete(p_case_id),
    'completedAt', v_investigation.completed_at,
    'updatedAt', v_investigation.updated_at
  );
end;
$$;

-- Older callers cannot fabricate the new confirmation. Their numeric values
-- can still be recorded; advice requires explicit confirmation through the new contract.
create or replace function public.save_case_investigations(
  p_case_id uuid, p_vitamin_d_level numeric, p_ionised_calcium numeric,
  p_body_weight_kg numeric, p_expected_revision integer
) returns jsonb language sql security definer set search_path = '' as $$
  select public.save_case_investigations(p_case_id,p_vitamin_d_level,p_ionised_calcium,
    p_body_weight_kg,p_expected_revision,null::boolean);
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
      'authoritativeHypocalcaemia', null,
      'hypocalcaemiaRevision', 0,
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
    'authoritativeHypocalcaemia', v_investigation.authoritative_hypocalcaemia,
    'hypocalcaemiaRevision', v_investigation.hypocalcaemia_revision,
    'revision', v_investigation.revision,
    'completed', public.phase3ca_investigations_complete(p_case_id),
    'completedAt', v_investigation.completed_at,
    'updatedAt', v_investigation.updated_at
  );
end;
$$;

-- Advice-only confirmation does not alter pathway or numeric investigation inputs.
create or replace function public.confirm_case_hypocalcaemia(
  p_case_id uuid, p_value boolean, p_expected_revision integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation public.investigations%rowtype;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can confirm hypocalcaemia' using errcode='42501';
  end if;
  if p_value is null or p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'An explicit hypocalcaemia confirmation and expected revision are required';
  end if;
  select * into v_case from public.clinical_cases where id=p_case_id for update;
  if not found or v_case.assigned_clinician_id is distinct from auth.uid()
    or v_case.status not in ('in_progress','evaluated') then
    raise exception 'Only your assigned current case can receive hypocalcaemia confirmation' using errcode='42501';
  end if;
  -- Preserve an already released decision and its frozen patient snapshot.
  if exists(select 1 from public.clinician_decisions where case_id=p_case_id
    and decision='approved' and released_at is not null) then
    raise exception 'An approved patient result cannot be changed through this confirmation';
  end if;
  select * into v_investigation from public.investigations where case_id=p_case_id for update;
  if not found or not public.phase3ca_investigations_complete(p_case_id) then
    raise exception 'Review and save the baseline investigations before confirming hypocalcaemia';
  end if;
  if v_investigation.hypocalcaemia_revision is distinct from p_expected_revision then
    raise exception 'Investigations changed. Reload before saving';
  end if;
  if v_investigation.authoritative_hypocalcaemia is distinct from p_value or v_investigation.hypocalcaemia_revision=0 then
    update public.investigations set authoritative_hypocalcaemia=p_value,
      hypocalcaemia_revision=hypocalcaemia_revision+1, updated_at=now() where case_id=p_case_id;
    update public.clinical_cases set results_review='{}'::jsonb,updated_at=now() where id=p_case_id;
  end if;
  return public.get_case_investigations(p_case_id);
end;
$$;


create or replace function public.submit_questionnaire_response(
    p_response_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_response public.questionnaire_responses%rowtype;
    v_case_id uuid;
    v_profile_gender text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if public.current_user_role() is distinct from 'patient' then
        raise exception 'Only patients can submit questionnaire responses';
    end if;

    select *
    into v_response
    from public.questionnaire_responses
    where id = p_response_id
    for update;

    if not found then
        raise exception 'Questionnaire response not found';
    end if;

    if v_response.patient_id is distinct from auth.uid() then
        raise exception 'You can only submit your own questionnaire response';
    end if;

    if v_response.status <> 'draft' then
        raise exception 'Questionnaire response has already been submitted';
    end if;

    -- Use the authenticated patient's profile, not a client-supplied sex answer.
    select lower(btrim(p.gender))
    into v_profile_gender
    from public.profiles as p
    where p.id = auth.uid();

    if v_profile_gender is null
        or v_profile_gender not in (
            'female', 'male', 'another term', 'another_term', 'other'
        ) then
        raise exception 'Sex recorded at birth is unavailable in your profile';
    end if;

    -- Active patient submission contract. Historical/catalog is_required flags
    -- are retained for readability and cannot expand this governed requirement.
    -- Sex authority is the profile validated above, never answers.sex.
    if exists (
        select 1
        from unnest(array['smoking', 'alcohol', 'dairyLessThan3Serves']
            || case when v_profile_gender = 'female'
                then array['postmenopausal'] else array[]::text[] end
        ) as required(field_key)
        where not (v_response.answers ? required.field_key)
           or v_response.answers -> required.field_key = 'null'::jsonb
    ) then
        raise exception 'All required questionnaire questions must be answered';
    end if;

    -- Match current UI answer types and fail closed on malformed/blank answers.
    if exists (
        select 1
        from unnest(array['smoking', 'alcohol']
            || case when v_profile_gender = 'female'
                then array['postmenopausal'] else array[]::text[] end
        ) as required(field_key)
        where jsonb_typeof(v_response.answers -> required.field_key) <> 'string'
           or v_response.answers ->> required.field_key not in ('Yes', 'No')
    ) then
        raise exception 'Required questionnaire choices must be Yes or No';
    end if;
    if jsonb_typeof(v_response.answers -> 'dairyLessThan3Serves') <> 'boolean' then
        raise exception 'Dairy threshold requires Yes or No';
    end if;

    update public.questionnaire_responses
    set
        status = 'submitted',
        submitted_at = now()
    where id = p_response_id;

    insert into public.clinical_cases (
        patient_id,
        questionnaire_response_id,
        status,
        submitted_at
    )
    values (
        auth.uid(),
        p_response_id,
        'clinician_input_required',
        now()
    )
    returning id into v_case_id;


    return v_case_id;
end;
$$;

create or replace function public.review_clinical_case_results(
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
    v_dairy_less_than_3 boolean;
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
    v_lifestyle_advice jsonb := '[]'::jsonb;
begin
    if auth.uid() is null or not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can review clinical case results';
    end if;

    select * into v_case
    from public.clinical_cases
    where id = p_case_id
    for update;

    if not found then
        raise exception 'Clinical case not found';
    end if;
    if v_case.assigned_clinician_id is distinct from auth.uid() then
        raise exception 'You can only review your assigned clinical case';
    end if;
    if v_case.status not in ('in_progress', 'evaluated') then
        raise exception 'Only current in-progress or evaluated cases can be reviewed';
    end if;
    if v_case.status = 'evaluated' and (
        v_case.rule_evaluation is null
        or (v_case.rule_evaluation ->> 'status') is distinct from 'complete'
        or (v_case.rule_evaluation ->> 'pathwayRevision')::integer
            is distinct from v_case.pathway_revision
    ) then
    raise exception 'A current terminal evaluation is required for results review';
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
    if v_case.status = 'evaluated'
        and (v_case.rule_evaluation ->> 'investigationRevision')::integer
        is distinct from v_investigation.revision
    then
        raise exception 'The terminal evaluation is stale for current Investigations';
    end if;

    select date_of_birth into v_date_of_birth
    from public.profiles
    where id = v_case.patient_id;

    if v_date_of_birth is null or v_date_of_birth > current_date then
        raise exception 'A valid patient date of birth is required for results review';
    end if;

    if jsonb_typeof(v_answers -> 'dairyLessThan3Serves') is distinct from 'boolean' then
      raise exception 'The current patient-reported dairy threshold answer is required';
    end if;
    v_dairy_less_than_3 := (v_answers ->> 'dairyLessThan3Serves')::boolean;
    if v_investigation.authoritative_hypocalcaemia is null or v_investigation.hypocalcaemia_revision=0 then
      raise exception 'Confirm hypocalcaemia before generating current patient advice';
    end if;

    v_age := extract(year from age(current_date, v_date_of_birth))::integer;
    v_older_people := v_age >= 65;

    if v_investigation.vitamin_d_level is null then
        v_vitamin_d_recommendation := null;
        v_vitamin_d_recheck := false;
    elsif v_investigation.vitamin_d_level < 40 then
        v_vitamin_d_recommendation :=
            'Take cholecalciferol 75 micrograms once daily for 6 weeks. Then take 25 micrograms once daily.';
        v_vitamin_d_recheck := v_investigation.vitamin_d_level < 25;
    elsif v_investigation.vitamin_d_level between 40 and 75 then
        v_vitamin_d_recommendation := 'Take cholecalciferol 25 micrograms once daily. Continue treatment.';
        v_vitamin_d_recheck := false;
    else
        v_vitamin_d_recommendation := null;
        v_vitamin_d_recheck := false;
    end if;

    v_hypocalcaemia := v_investigation.authoritative_hypocalcaemia;
    v_calcium_supplement_required :=
        v_dairy_less_than_3 or v_hypocalcaemia;
    if v_calcium_supplement_required then
        v_calcium_recommendation := 'Take calcium 600 mg once daily.';
    else
        v_calcium_recommendation := null;
    end if;

    if v_older_people and v_investigation.body_weight_kg is not null then
        v_protein_min_grams := v_investigation.body_weight_kg * 1.0;
        v_protein_max_grams := v_investigation.body_weight_kg * 1.2;
        v_protein_recommendation :=
            'Protein target: 1.0-1.2 g/kg bodyweight daily';
    else
        v_protein_min_grams := null;
        v_protein_max_grams := null;
        v_protein_recommendation := null;
    end if;

    -- Questionnaire choices are Yes/No. Also accept equivalent boolean JSON.
    -- No, missing and unknown answers do not generate cessation/reduction advice.
    if lower(btrim(coalesce(v_answers ->> 'smoking', ''))) in ('yes', 'true') then
        v_lifestyle_advice := v_lifestyle_advice
            || jsonb_build_array('Stop smoking.');
    end if;

    if lower(btrim(coalesce(v_answers ->> 'alcohol', ''))) in ('yes', 'true') then
        v_lifestyle_advice := v_lifestyle_advice
            || jsonb_build_array('Reduce alcohol intake.');
    end if;

    v_lifestyle_advice := v_lifestyle_advice
      || jsonb_build_array('Do regular weight-bearing exercise.');

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
        'authoritativeHypocalcaemia', v_hypocalcaemia,
        'dairyLessThan3Serves', v_dairy_less_than_3,
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
        'lifestyleAdvice', v_lifestyle_advice,
        'source', jsonb_build_object(
        'adviceContractVersion', 'songyi-advice-20261009',
        'hypocalcaemiaRevision', v_investigation.hypocalcaemia_revision,
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

create or replace function public.phase3_final_common_advice(p_results_review jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(value order by position),'[]'::jsonb)
  from (
    select value,min(position) as position from (
      select position,value from (values
        (1,p_results_review #> '{vitaminD,recommendation}'),
        (2,case when p_results_review #> '{vitaminD,recheckBeforeTreatment}' = 'true'::jsonb
          then to_jsonb('Recheck vitamin D before starting osteoporosis treatment.'::text) end),
        (3,p_results_review #> '{calcium,recommendation}'),
        (1000,p_results_review #> '{protein,recommendation}')
      ) as recommendations(position,value)
      union all
      select 100+ordinal::integer,value from jsonb_array_elements(
        coalesce(p_results_review->'lifestyleAdvice','[]'::jsonb)) with ordinality as lifestyle(value,ordinal)
    ) as supplied where jsonb_typeof(value)='string' and value <> '""'::jsonb
    group by value
  ) as ordered;
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
  v_hypocalcaemia_revision integer;
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

  if v_case.results_review #>> '{source,adviceContractVersion}' is distinct from 'songyi-advice-20261009'
    or v_case.results_review = '{}'::jsonb
    or not public.phase3ca_investigations_complete(p_case_id)
  then
    raise exception 'Current candidate results review is not available';
  end if;

  select revision,hypocalcaemia_revision into v_investigation_revision,v_hypocalcaemia_revision
  from public.investigations
  where case_id = p_case_id;

  select revision into v_questionnaire_revision
  from public.questionnaire_responses
  where id = v_case.questionnaire_response_id
    and status = 'submitted';

  if (v_case.results_review #>> '{source,hypocalcaemiaRevision}')::integer is distinct from v_hypocalcaemia_revision
    or (v_case.results_review #>> '{source,investigationRevision}')::integer
      is distinct from v_investigation_revision
    or (v_case.results_review #>> '{source,questionnaireRevision}')::integer
      is distinct from v_questionnaire_revision
  then
    raise exception 'Candidate results review is stale and must be regenerated';
  end if;

  return v_case.results_review;
end;
$$;

create or replace function public.review_pathway_evaluation(
  p_case_id uuid,
  p_decision text,
  p_clinician_message text,
  p_expected_pathway_revision integer,
  p_expected_investigation_revision integer,
  p_expected_questionnaire_revision integer,
  p_expected_hypocalcaemia_revision integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation_revision integer;
  v_questionnaire_revision integer;
  v_hypocalcaemia_revision integer;
  v_actions jsonb;
  v_common_advice jsonb;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can review pathway evaluations';
  end if;
  if p_decision is null or p_decision not in ('approved', 'withheld') then
    raise exception 'Decision must be approved or withheld';
  end if;
  if nullif(btrim(p_clinician_message), '') is null then
    if p_decision = 'withheld' then
      raise exception 'A reason is required for withholding this recommendation';
    end if;
    raise exception 'A clinician message is required for patient release';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then raise exception 'Clinical case not found'; end if;
  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only review your assigned clinical case';
  end if;
  if v_case.status <> 'evaluated' or v_case.rule_evaluation is null then
    raise exception 'Only evaluated clinical cases can be reviewed';
  end if;
  if v_case.pathway_revision is distinct from p_expected_pathway_revision
    or (v_case.rule_evaluation ->> 'pathwayRevision')::integer
       is distinct from v_case.pathway_revision
  then
    raise exception 'Pathway evaluation is out of date';
  end if;

  select revision,hypocalcaemia_revision into v_investigation_revision,v_hypocalcaemia_revision
  from public.investigations
  where case_id = p_case_id;
  if v_investigation_revision is distinct from p_expected_investigation_revision
    or (v_case.rule_evaluation ->> 'investigationRevision')::integer
       is distinct from v_investigation_revision
    or not public.phase3ca_investigations_complete(p_case_id)
  then
    raise exception 'Investigations changed. Re-evaluate before deciding';
  end if;

  select revision into v_questionnaire_revision
  from public.questionnaire_responses
  where id = v_case.questionnaire_response_id and status = 'submitted';

  if p_decision = 'approved' then
    if v_hypocalcaemia_revision is distinct from p_expected_hypocalcaemia_revision then
      raise exception 'Advice confirmation changed. Reload before deciding';
    end if;
    if (v_case.rule_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261009-care'
      and ((v_case.rule_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261009-bmd'
          and v_case.rule_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261008')
        or exists (select 1 from jsonb_array_elements(v_case.rule_evaluation -> 'trace') as t
          where t ->> 'pathwayId' = 'PATHWAY1' and t ->> 'nodeId' = 'RESIDENTIAL_OR_FRAILTY')
        or (v_case.rule_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261009-bmd'
          and exists (select 1 from jsonb_array_elements(v_case.rule_evaluation -> 'trace') as t
            where t ->> 'pathwayId' = 'PATHWAY1'
              and t ->> 'nodeId' in ('T_SCORE_CHECK', 'HIGH_RISK_CHECK')))))
      or v_case.rule_evaluation -> 'eligibilityContext'
         is distinct from public.songyi_p1_eligibility_context(p_case_id) then
      raise exception 'Current P1 eligibility is required before approval. Re-evaluate';
    end if;
    if v_case.results_review #>> '{source,adviceContractVersion}' is distinct from 'songyi-advice-20261009'
      or (v_case.results_review #>> '{source,hypocalcaemiaRevision}')::integer is distinct from v_hypocalcaemia_revision
      or v_questionnaire_revision is distinct from p_expected_questionnaire_revision
      or v_case.results_review = '{}'::jsonb
      or (v_case.results_review #>> '{source,investigationRevision}')::integer
         is distinct from v_investigation_revision
      or (v_case.results_review #>> '{source,questionnaireRevision}')::integer
         is distinct from v_questionnaire_revision
    then
      raise exception 'Current Common Advice is required before approval';
    end if;
    v_actions := v_case.rule_evaluation -> 'actions';
    if jsonb_typeof(v_actions) is distinct from 'array'
      or jsonb_array_length(v_actions) = 0
    then
      raise exception 'An actionable care recommendation is required for approval';
    end if;
    v_common_advice := public.phase3_final_common_advice(v_case.results_review);
  else
    v_actions := '[]'::jsonb;
    v_common_advice := '[]'::jsonb;
  end if;

  insert into public.clinician_decisions (
    case_id,
    clinician_id,
    decision,
    notes,
    pathway_revision,
    investigation_revision,
    questionnaire_revision,
    approved_actions_snapshot,
    approved_common_advice_snapshot,
    released_at
  ) values (
    p_case_id,
    auth.uid(),
    p_decision,
    nullif(btrim(p_clinician_message), ''),
    v_case.pathway_revision,
    v_investigation_revision,
    case when p_decision = 'approved' then v_questionnaire_revision end,
    v_actions,
    v_common_advice,
    case when p_decision = 'approved' then now() end
  )
  on conflict (case_id) do update set
    clinician_id = excluded.clinician_id,
    decision = excluded.decision,
    notes = excluded.notes,
    pathway_revision = excluded.pathway_revision,
    investigation_revision = excluded.investigation_revision,
    questionnaire_revision = excluded.questionnaire_revision,
    approved_actions_snapshot = excluded.approved_actions_snapshot,
    approved_common_advice_snapshot = excluded.approved_common_advice_snapshot,
    released_at = excluded.released_at,
    updated_at = now();
end;
$$;
-- Legacy clients may withhold, but cannot approve advice they have not bound to
-- the clinician-confirmation revision. Never infer an expected revision for them.
create or replace function public.review_pathway_evaluation(
  p_case_id uuid,p_decision text,p_clinician_message text,
  p_expected_pathway_revision integer,p_expected_investigation_revision integer,
  p_expected_questionnaire_revision integer
) returns void language sql security definer set search_path = '' as $$
  select public.review_pathway_evaluation(p_case_id,p_decision,p_clinician_message,
    p_expected_pathway_revision,p_expected_investigation_revision,
    p_expected_questionnaire_revision,null::integer);
$$;


revoke all on function public.phase3ca_investigations_complete(uuid) from public,anon,authenticated;

revoke all on function public.save_case_investigations(uuid,numeric,numeric,numeric,integer,boolean) from public,anon,authenticated;
grant execute on function public.save_case_investigations(uuid,numeric,numeric,numeric,integer,boolean) to authenticated;

revoke all on function public.save_case_investigations(uuid,numeric,numeric,numeric,integer) from public,anon,authenticated;
grant execute on function public.save_case_investigations(uuid,numeric,numeric,numeric,integer) to authenticated;

revoke all on function public.get_case_investigations(uuid) from public,anon,authenticated;
grant execute on function public.get_case_investigations(uuid) to authenticated;

revoke all on function public.confirm_case_hypocalcaemia(uuid,boolean,integer) from public,anon,authenticated;
grant execute on function public.confirm_case_hypocalcaemia(uuid,boolean,integer) to authenticated;

revoke all on function public.submit_questionnaire_response(uuid) from public,anon,authenticated;
grant execute on function public.submit_questionnaire_response(uuid) to authenticated;

revoke all on function public.review_clinical_case_results(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.review_clinical_case_results(uuid,integer,integer) to authenticated;

revoke all on function public.phase3_final_common_advice(jsonb) from public,anon,authenticated;

revoke all on function public.get_clinical_case_results_review(uuid) from public,anon,authenticated;
grant execute on function public.get_clinical_case_results_review(uuid) to authenticated;

revoke all on function public.review_pathway_evaluation(uuid,text,text,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.review_pathway_evaluation(uuid,text,text,integer,integer,integer) to authenticated;

do $$begin
  if to_regprocedure('public.review_clinical_case_results(uuid)') is not null then
    execute 'revoke all on function public.review_clinical_case_results(uuid) from public,anon,authenticated';
  end if;
end;$$;
revoke all on function public.review_pathway_evaluation(uuid,text,text,integer,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.review_pathway_evaluation(uuid,text,text,integer,integer,integer,integer) to authenticated;
notify pgrst, 'reload schema';
commit;