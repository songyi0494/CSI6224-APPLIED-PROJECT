-- Bounded P1/P2 contract repair. No historical rows are rewritten.
begin;

create or replace function public.songyi_p1_eligibility_context(p_case_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.clinical_cases%rowtype;
  v_profile public.profiles%rowtype;
  v_response public.questionnaire_responses%rowtype;
  v_sex text;
  v_age integer;
  v_menopause boolean;
begin
  select * into v_case from public.clinical_cases where id = p_case_id;
  select * into v_profile from public.profiles where id = v_case.patient_id for share;
  select * into v_response from public.questionnaire_responses
    where id = v_case.questionnaire_response_id and patient_id = v_case.patient_id
      and status = 'submitted' for share;
  v_sex := lower(btrim(v_profile.gender));
  if v_profile.date_of_birth is not null and v_profile.date_of_birth <= current_date then
    v_age := extract(year from age(current_date, v_profile.date_of_birth))::integer;
  end if;
  if v_sex = 'female' then
    case lower(btrim(v_response.answers ->> 'postmenopausal'))
      when 'yes' then v_menopause := true;
      when 'true' then v_menopause := true;
      when 'no' then v_menopause := false;
      when 'false' then v_menopause := false;
      else v_menopause := null;
    end case;
  end if;
  return jsonb_build_object(
    'sex', v_sex, 'age', v_age, 'postmenopausal', v_menopause,
    'questionnaireRevision', v_response.revision, 'ageAsOf', current_date
  );
end;
$$;
revoke all on function public.songyi_p1_eligibility_context(uuid) from public, anon, authenticated;

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
    'investigation_revision', v_investigation_revision,
    'eligibility_context', public.songyi_p1_eligibility_context(p_case_id)
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


  -- Only the newly authorised contract fields change their meaning here.
  if p_field_key = 'eGFR' and jsonb_typeof(p_value) is distinct from 'boolean' then
    raise exception 'eGFR must confirm the >=30 mL/min threshold with Yes or No';
  end if;
  if p_field_key = 'antiresorptiveTreatmentDuration' then
    raise exception 'Confirm treatment for more than 12 months using the current duration question';
  end if;
  if p_field_key = 'antiresorptiveTreatmentOver12Months'
    and jsonb_typeof(p_value) is distinct from 'boolean' then
    raise exception 'Treatment for more than 12 months requires Yes or No';
  end if;
  if p_field_key = 'p1DemographicEligible' then
    raise exception 'Demographic eligibility comes from the patient profile and submitted questionnaire';
  end if;
  if p_field_key = 'minimalTraumaFracture' and (
    jsonb_typeof(p_value) is distinct from 'string'
    or p_value #>> '{}' not in ('yes', 'no', 'not_sure')
  ) then
    raise exception 'Confirm the fracture mechanism using Yes, No or Not sure';
  end if;
  if p_field_key = 'fractureSite' and (
    jsonb_typeof(p_value) is distinct from 'string'
    or p_value #>> '{}' not in (
      'hip', 'vertebral', 'pelvis', 'upper_arm', 'forearm', 'leg', 'ribs',
      'hand', 'foot', 'face', 'ankle', 'not_sure'
    )
  ) then
    raise exception 'Confirm a separate fracture site or select Not sure';
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

create or replace function public.save_rule_evaluation(
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
  v_eligibility jsonb;
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


  v_eligibility := public.songyi_p1_eligibility_context(p_case_id);
  if p_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261008'
    or p_evaluation -> 'eligibilityContext' is distinct from v_eligibility then
    raise exception 'Eligibility information changed or uses an old contract. Re-evaluate';
  end if;
  if not coalesce(
    (v_eligibility ->> 'sex' = 'female' and v_eligibility ->> 'postmenopausal' = 'true')
    or (v_eligibility ->> 'sex' = 'male' and (v_eligibility ->> 'age')::integer > 50), false
  ) then
    raise exception 'P1 demographic eligibility is missing or not met';
  end if;
  if v_case.clinician_facts ->> 'minimalTraumaFracture' is distinct from 'yes'
    or not coalesce(v_case.clinician_facts ->> 'fractureSite' in (
      'hip', 'vertebral', 'pelvis', 'upper_arm', 'forearm', 'leg', 'ribs'
    ), false)
    or jsonb_typeof(v_case.clinician_facts -> 'eGFR') is distinct from 'boolean'
  then
    raise exception 'Current structured P1 eligibility and Boolean eGFR confirmation are required';
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

revoke all on function public.get_pathway_case_context(uuid) from public, anon;
revoke all on function public.save_pathway_answer(uuid, text, jsonb) from public, anon;
revoke all on function public.save_rule_evaluation(uuid, jsonb, integer, integer) from public, anon;
grant execute on function public.get_pathway_case_context(uuid) to authenticated;
grant execute on function public.save_pathway_answer(uuid, text, jsonb) to authenticated;
grant execute on function public.save_rule_evaluation(uuid, jsonb, integer, integer) to authenticated;
create or replace function public.review_pathway_evaluation(
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
    if v_case.rule_evaluation ->> 'contractVersion' is distinct from 'songyi-p1p2-20261008'
      or v_case.rule_evaluation -> 'eligibilityContext'
         is distinct from public.songyi_p1_eligibility_context(p_case_id) then
      raise exception 'Current P1 eligibility is required before approval. Re-evaluate';
    end if;
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
revoke all on function public.review_pathway_evaluation(uuid, text, text, integer, integer, integer) from public, anon;
grant execute on function public.review_pathway_evaluation(uuid, text, text, integer, integer, integer) to authenticated;
commit;
