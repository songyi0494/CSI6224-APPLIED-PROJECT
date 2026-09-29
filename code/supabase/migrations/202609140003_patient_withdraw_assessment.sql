begin;

create or replace function public.withdraw_assessment_for_edit(
  p_id uuid,
  p_revision integer,
  p_updated_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a public.assessments;
  cf jsonb;
begin
  if not public.has_role('patient') then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select *
  into a
  from public.assessments
  where id = p_id
  for update;

  if not found or a.patient_id <> auth.uid() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  if a.revision is distinct from p_revision or
     a.updated_at is distinct from p_updated_at then
    raise exception 'Assessment changed. Reload and try again.';
  end if;

  select clinician_facts
  into cf
  from public.clinical_inputs
  where assessment_id = p_id and revision = p_revision;

  if a.status <> 'clinician_input_required' or
     coalesce(cf, '{}'::jsonb) <> '{}'::jsonb or
     exists (
       select 1
       from public.evaluations e
       where e.assessment_id = p_id and e.revision = p_revision
     ) or
     exists (
       select 1
       from public.clinician_decisions d
       where d.assessment_id = p_id and d.revision = p_revision
     ) then
    raise exception 'This assessment is already being reviewed and can no longer be edited directly. Contact your clinician if information needs to be corrected.';
  end if;

  update public.assessments
  set status = 'draft',
      pathway = null,
      routing_reason = null,
      submitted_at = null,
      updated_at = clock_timestamp()
  where id = p_id;

  return public.get_assessment(p_id);
end $$;

revoke all on function public.withdraw_assessment_for_edit(uuid,integer,timestamptz)
from public, anon, authenticated;
grant execute on function public.withdraw_assessment_for_edit(uuid,integer,timestamptz)
to authenticated;

commit;
