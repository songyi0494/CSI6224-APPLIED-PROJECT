begin;

-- The existing decision row is the single decision authority. These additive
-- columns freeze only the patient-safe payload for the approved revision.
alter table public.clinician_decisions
  add column if not exists investigation_revision integer,
  add column if not exists questionnaire_revision integer,
  add column if not exists approved_actions_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists approved_common_advice_snapshot jsonb not null default '[]'::jsonb,
  add column if not exists released_at timestamptz;

alter table public.clinician_decisions
  drop constraint if exists clinician_decisions_decision_check;

alter table public.clinician_decisions
  add constraint clinician_decisions_decision_check
  check (decision in ('approved', 'rejected', 'withheld'));

alter table public.clinician_decisions
  add constraint clinician_decisions_approved_actions_snapshot_check
  check (jsonb_typeof(approved_actions_snapshot) = 'array') not valid,
  add constraint clinician_decisions_approved_common_advice_snapshot_check
  check (jsonb_typeof(approved_common_advice_snapshot) = 'array') not valid;

-- Clinician-only case detail now returns the already-persisted evaluator result.
-- Patient access remains excluded because this RPC requires an approved clinician.
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
    raise exception 'Clinical case is not available' using errcode = '42501';
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
    'updated_at', v_case.updated_at,
    'pathway_revision', v_case.pathway_revision,
    'questionnaire_response_id', v_case.questionnaire_response_id,
    'assigned_clinician_id', v_case.assigned_clinician_id,
    'rule_evaluation', v_case.rule_evaluation
  );
end;
$$;

-- Preserve the existing Common Advice rules. The only lifecycle change is that
-- an assigned clinician may generate the candidate after terminal evaluation,
-- provided the evaluation and every source revision are still current.
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

  begin
    v_dietary_dairy_servings := nullif(
      v_answers ->> 'dietaryDairyServings', ''
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
    v_vitamin_d_recommendation := 'Cholecalciferol 25 microg daily ongoing';
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

create or replace function public.phase3_final_common_advice(
  p_results_review jsonb
) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(item.value order by item.position), '[]'::jsonb)
  from (
    select position, value
    from (
      values
        (1, p_results_review #> '{vitaminD,recommendation}'),
        (2, p_results_review #> '{calcium,recommendation}'),
        (3, p_results_review #> '{protein,recommendation}')
    ) as recommendations(position, value)
    where jsonb_typeof(value) = 'string' and value <> '""'::jsonb
    union all
    select 100 + ordinal::integer, value
    from jsonb_array_elements(
      coalesce(p_results_review -> 'lifestyleAdvice', '[]'::jsonb)
    ) with ordinality as lifestyle(value, ordinal)
    where jsonb_typeof(value) = 'string' and value <> '""'::jsonb
  ) as item;
$$;

revoke all on function public.review_pathway_evaluation(uuid, text, text)
from public, anon, authenticated;
drop function public.review_pathway_evaluation(uuid, text, text);

create function public.review_pathway_evaluation(
  p_case_id uuid,
  p_decision text,
  p_clinician_message text,
  p_expected_pathway_revision integer,
  p_expected_investigation_revision integer,
  p_expected_questionnaire_revision integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_investigation_revision integer;
  v_questionnaire_revision integer;
  v_actions jsonb;
  v_common_advice jsonb;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can review pathway evaluations'
      using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'withheld') then
    raise exception 'Decision must be approved or withheld';
  end if;
  if p_decision = 'approved'
    and nullif(btrim(p_clinician_message), '') is null
  then
    raise exception 'A clinician message is required for patient release';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id
  for update;

  if not found then raise exception 'Clinical case not found'; end if;
  if v_case.assigned_clinician_id is distinct from auth.uid() then
    raise exception 'You can only review your assigned clinical case'
      using errcode = '42501';
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

  select revision into v_investigation_revision
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
    if v_questionnaire_revision is distinct from p_expected_questionnaire_revision
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

create or replace function public.get_patient_approved_results()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'caseId', d.case_id,
      'reviewedAt', d.released_at,
      'lifestyleRecommendations', d.approved_common_advice_snapshot,
      'careRecommendation', d.approved_actions_snapshot,
      'clinicianMessage', d.notes
    ) order by d.released_at desc
  ), '[]'::jsonb)
  from public.clinician_decisions d
  join public.clinical_cases c on c.id = d.case_id
  where auth.uid() is not null
    and c.patient_id = auth.uid()
    and d.decision = 'approved'
    and d.released_at is not null;
$$;

revoke all on function public.phase3_final_common_advice(jsonb)
from public, anon, authenticated;
revoke all on function public.review_pathway_evaluation(
  uuid, text, text, integer, integer, integer
) from public, anon, authenticated;
revoke all on function public.get_patient_approved_results()
from public, anon, authenticated;

grant execute on function public.review_pathway_evaluation(
  uuid, text, text, integer, integer, integer
) to authenticated;
grant execute on function public.get_patient_approved_results()
to authenticated;

commit;
