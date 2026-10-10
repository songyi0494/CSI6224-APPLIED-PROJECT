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
