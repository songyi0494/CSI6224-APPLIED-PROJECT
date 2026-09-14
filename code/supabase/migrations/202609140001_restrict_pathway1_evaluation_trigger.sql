begin;

create or replace function public.complete_evaluation(
  p_actor uuid,
  p_id uuid,
  p_revision integer,
  p_result jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a public.assessments;
  f jsonb;
  next_status text;
  existing_evaluation uuid;
begin
  select * into a from public.assessments where id=p_id for update;
  if not found then raise exception 'Not authorised' using errcode='42501'; end if;
  if a.revision is distinct from p_revision then raise exception 'Assessment changed'; end if;
  select facts into f from public.clinical_inputs
  where assessment_id=p_id and revision=p_revision;

  if not (
    (a.status='draft'
      and a.patient_id=p_actor
      and f->>'osteoporosisTreatmentStatus'='true'
      and exists(select 1 from public.profiles where id=p_actor and role='patient'))
    or
    (a.status='clinician_input_required'
      and exists(select 1 from public.profiles where id=p_actor and role='clinician' and approval_status='approved')
      and (a.assigned_clinician_id is null or a.assigned_clinician_id=p_actor))
  ) then raise exception 'Not authorised' using errcode='42501'; end if;

  if p_result->>'rule_version' is null
    or p_result->>'decision' not in ('action_taken','no_action','not_applicable','needs_more_information','not_integrated')
  then raise exception 'Invalid engine result'; end if;

  next_status := case
    when p_result->>'decision'='action_taken' then 'awaiting_review'
    when p_result->>'decision'='needs_more_information'
      and jsonb_array_length(coalesce(p_result->'missing_inputs','[]'::jsonb))>0
      and not exists (
        select 1
        from jsonb_array_elements_text(coalesce(p_result->'missing_inputs','[]'::jsonb)) as missing(value)
        where missing.value not in (
          'eGFR',
          'clinicalFrailtyScore',
          'lifeExpectancy',
          'knownPoorMedicationAdherence',
          'cognitiveImpairment',
          'testAvailable',
          'testWithinLast2Years',
          'T-score',
          'hipVertebralOrMultipleFracturesInLast24M',
          'highRisk',
          'yearSincePostmenopausal',
          'isRobustWoman'
        )
      )
      then 'clinician_input_required'
    else 'manual_review'
  end;

  select id into existing_evaluation
  from public.evaluations
  where assessment_id=p_id and revision=p_revision;
  if existing_evaluation is null then
    insert into public.evaluations(assessment_id,revision,result,rule_version)
    values (p_id,p_revision,p_result,p_result->>'rule_version');
  else
    update public.evaluations
    set result=p_result,
        rule_version=p_result->>'rule_version',
        created_at=clock_timestamp()
    where id=existing_evaluation;
  end if;

  update public.assessments
  set status=next_status,
      pathway=p_result->>'pathway',
      routing_reason=p_result->>'routing_reason',
      submitted_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=p_id;
end $$;

revoke all on function public.complete_evaluation(uuid,uuid,integer,jsonb)
from public,anon,authenticated;
grant execute on function public.complete_evaluation(uuid,uuid,integer,jsonb)
to service_role;

commit;
