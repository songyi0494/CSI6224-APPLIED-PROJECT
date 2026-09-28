begin;

alter table public.assessments
drop constraint if exists assessments_status_check;

alter table public.assessments
add constraint assessments_status_check
check (status in (
  'draft',
  'clinician_input_required',
  'awaiting_review',
  'manual_review',
  'approved',
  'withheld',
  'needs_more_information',
  'follow_up_required'
));

alter table public.clinical_inputs
add column if not exists clinician_facts jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clinical_inputs_clinician_facts_check'
      and conrelid = 'public.clinical_inputs'::regclass
  ) then
    alter table public.clinical_inputs
    add constraint clinical_inputs_clinician_facts_check
    check (jsonb_typeof(clinician_facts) = 'object');
  end if;
end $$;

create unique index if not exists assessments_one_active_per_patient_idx
on public.assessments(patient_id)
where status in (
  'draft',
  'clinician_input_required',
  'awaiting_review',
  'manual_review',
  'needs_more_information'
);

create or replace function public.save_assessment(
  p_id uuid,
  p_expected_revision integer,
  p_facts jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a public.assessments;
  new_revision integer;
  previous_clinician_facts jsonb := '{}'::jsonb;
begin
  if not public.has_role('patient') then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Invalid revision';
  end if;
  if jsonb_typeof(p_facts) is distinct from 'object' or
     octet_length(p_facts::text) > 50000 then
    raise exception 'Invalid clinical input';
  end if;

  p_facts := jsonb_strip_nulls(jsonb_build_object(
    'osteoporosisTreatmentStatus', p_facts->'osteoporosisTreatmentStatus',
    'age', (
      select to_jsonb(date_part('year', age(clock_timestamp(), p.date_of_birth))::integer)
      from public.profiles p
      where p.id = auth.uid() and p.date_of_birth is not null
    ),
    'sex', p_facts->'sex',
    'postmenopausal', p_facts->'postmenopausal',
    'minimalTraumaFracture', p_facts->'minimalTraumaFracture',
    'fractureSite', p_facts->'fractureSite',
    'liveInResidentialCare', p_facts->'liveInResidentialCare'
  ));

  perform pg_advisory_xact_lock(hashtextextended(p_id::text, 0));
  select * into a from public.assessments where id = p_id for update;
  if found then
    if a.patient_id <> auth.uid() then
      raise exception 'Not authorised' using errcode='42501';
    end if;
    if a.revision = p_expected_revision + 1 and exists (
      select 1
      from public.clinical_inputs
      where assessment_id = p_id and revision = a.revision and facts = p_facts
    ) then
      return public.get_assessment(p_id);
    end if;
    if a.revision is distinct from p_expected_revision or
       a.status <> 'draft' then
      raise exception 'Assessment changed. Reload before editing';
    end if;
    select clinician_facts
    into previous_clinician_facts
    from public.clinical_inputs
    where assessment_id = p_id and revision = a.revision;
    new_revision := a.revision + 1;
    update public.assessments
    set revision = new_revision,
        status = 'draft',
        pathway = null,
        routing_reason = null,
        updated_at = clock_timestamp()
    where id = p_id;
  else
    if p_expected_revision <> 0 then
      raise exception 'Assessment no longer available';
    end if;
    if exists (
      select 1
      from public.assessments existing
      where existing.patient_id = auth.uid()
        and existing.status in (
          'draft',
          'clinician_input_required',
          'awaiting_review',
          'manual_review',
          'needs_more_information'
        )
    ) then
      raise exception 'Assessment already in progress';
    end if;
    new_revision := 1;
    insert into public.assessments(id, patient_id, revision, status)
    values (p_id, auth.uid(), new_revision, 'draft');
  end if;

  insert into public.clinical_inputs(
    assessment_id,
    revision,
    facts,
    clinician_facts
  ) values (
    p_id,
    new_revision,
    p_facts,
    coalesce(previous_clinician_facts, '{}'::jsonb)
  );
  return public.get_assessment(p_id);
end $$;

create or replace function public.save_pathway1_clinician_input(
  p_id uuid,
  p_revision integer,
  p_updated_at timestamptz,
  p_clinician_facts jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a public.assessments;
begin
  if not public.has_role('clinician') then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if jsonb_typeof(p_clinician_facts) is distinct from 'object' or
     octet_length(p_clinician_facts::text) > 50000 then
    raise exception 'Invalid clinical input';
  end if;
  select * into a from public.assessments where id = p_id for update;
  if not found or not public.can_review(p_id) then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if a.revision is distinct from p_revision or
     a.updated_at is distinct from p_updated_at or
     a.status <> 'clinician_input_required' or
     a.pathway is distinct from 'PATHWAY1' then
    raise exception 'Assessment changed. Reload before entering clinical input';
  end if;
  update public.clinical_inputs
  set clinician_facts = p_clinician_facts
  where assessment_id = p_id and revision = p_revision;
  update public.assessments
  set assigned_clinician_id = auth.uid(),
      updated_at = clock_timestamp()
  where id = p_id;
  return public.get_assessment(p_id);
end $$;

create or replace function public.submit_pathway1_for_clinician_input(
  p_id uuid,
  p_revision integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a public.assessments;
  f jsonb;
begin
  if not public.has_role('patient') then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  select * into a from public.assessments where id = p_id for update;
  if not found or a.patient_id <> auth.uid() then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if a.revision is distinct from p_revision then
    raise exception 'Assessment changed. Reload before submitting';
  end if;
  if a.status = 'clinician_input_required' and a.pathway = 'PATHWAY1' then
    return public.get_assessment(p_id);
  end if;
  if a.status <> 'draft' then
    raise exception 'Assessment changed. Reload before submitting';
  end if;
  select facts
  into f
  from public.clinical_inputs
  where assessment_id = p_id and revision = p_revision;
  if f->>'osteoporosisTreatmentStatus' = 'true' then
    raise exception 'Pathway 2 submission uses the evaluator boundary';
  end if;
  update public.assessments
  set status = 'clinician_input_required',
      pathway = 'PATHWAY1',
      routing_reason = 'No previous or current osteoporosis treatment was recorded.',
      submitted_at = coalesce(submitted_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where id = p_id;
  return public.get_assessment(p_id);
end $$;

revoke all on function public.save_assessment(uuid,integer,jsonb)
from public, anon, authenticated;
grant execute on function public.save_assessment(uuid,integer,jsonb)
to authenticated;

revoke all on function public.submit_pathway1_for_clinician_input(uuid,integer)
from public, anon, authenticated;
grant execute on function public.submit_pathway1_for_clinician_input(uuid,integer)
to authenticated;

revoke all on function public.save_pathway1_clinician_input(uuid,integer,timestamptz,jsonb)
from public, anon, authenticated;
grant execute on function public.save_pathway1_clinician_input(uuid,integer,timestamptz,jsonb)
to authenticated;

grant execute on function public.has_role(text),
  public.can_review(uuid),
  public.owns_assessment(uuid),
  public.get_assessment(uuid),
  public.list_assessments(),
  public.record_decision(uuid,integer,timestamptz,uuid,text,text)
to authenticated;

commit;
