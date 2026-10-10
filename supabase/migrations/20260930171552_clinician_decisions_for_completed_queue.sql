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
  v_display_status text;
  v_decision_notes text;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read clinical case detail';
  end if;

  select * into v_case
  from public.clinical_cases
  where id = p_case_id;

  if not found then
    raise exception 'Clinical case is not available';
  end if;
  if v_case.assigned_clinician_id is distinct from auth.uid()
    and not (
      v_case.assigned_clinician_id is null
      and v_case.status = 'clinician_input_required'
    ) then
    raise exception 'Clinical case is not available';
  end if;

  -- Only the current assigned clinician's decision for current inputs is final.
  -- The stored clinical_cases.status stays evaluated; this is a UI projection.
  v_display_status := v_case.status;
  if v_case.status = 'evaluated' then
    select d.decision, d.notes
    into v_display_status, v_decision_notes
    from public.clinician_decisions as d
    where d.case_id = v_case.id
      and d.clinician_id = v_case.assigned_clinician_id
      and d.decision in ('approved', 'withheld')
      and d.pathway_revision = v_case.pathway_revision
      and d.pathway_revision =
          (v_case.rule_evaluation ->> 'pathwayRevision')::integer
      and d.investigation_revision =
          (v_case.rule_evaluation ->> 'investigationRevision')::integer
      and d.investigation_revision = (
          select i.revision from public.investigations as i
          where i.case_id = v_case.id
      )
      and (
        d.decision = 'withheld'
        or (
          d.released_at is not null
          and d.questionnaire_revision = (
            select q.revision from public.questionnaire_responses as q
            where q.id = v_case.questionnaire_response_id
              and q.status = 'submitted'
          )
        )
      );
    v_display_status := coalesce(v_display_status, v_case.status);
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
    'status', v_display_status,
    'decision_notes', v_decision_notes,
    'submitted_at', v_case.submitted_at,
    'updated_at', v_case.updated_at,
    'pathway_revision', v_case.pathway_revision,
    'questionnaire_response_id', v_case.questionnaire_response_id,
    'assigned_clinician_id', v_case.assigned_clinician_id,
    'rule_evaluation', v_case.rule_evaluation
  );
end;
$$;

revoke all on function public.get_clinical_case_detail(uuid) from public, anon;
grant execute on function public.get_clinical_case_detail(uuid) to authenticated;

-- Dashboard and detail use the same decision-derived status.
create or replace function public.get_clinician_case_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_results jsonb;
begin
  if auth.uid() is null or not public.is_approved_clinician() then
    raise exception 'Only approved clinicians can read the clinical work queue';
  end if;

  select coalesce(
      jsonb_agg(public.get_clinical_case_detail(c.id)
                order by c.updated_at desc),
      '[]'::jsonb
  ) into v_results
  from public.clinical_cases as c
  where c.assigned_clinician_id = auth.uid()
    or (c.assigned_clinician_id is null
        and c.status = 'clinician_input_required');

  return v_results;
end;
$$;

revoke all on function public.get_clinician_case_list() from public, anon;
grant execute on function public.get_clinician_case_list() to authenticated;
