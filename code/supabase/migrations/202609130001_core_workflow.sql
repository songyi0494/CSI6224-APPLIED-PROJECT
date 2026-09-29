begin;

-- stop rather than overwrite an unknown dashboard-managed schema
DO $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public'
    and table_name in ('profiles','assessments','clinical_inputs','evaluations','clinician_decisions')) then
    raise exception 'Existing clinical tables detected. Export and reconcile the schema before applying this baseline.';
  end if;
end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 200),
  email text not null,
  role text not null check (role in ('patient','clinician','admin')),
  approval_status text check (approval_status in ('pending','approved','rejected')),
  date_of_birth date,
  sex_at_birth text check (sex_at_birth in ('female','male','other','not_provided')),
  reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check ((role = 'clinician' and approval_status is not null) or (role <> 'clinician' and approval_status is null))
);
create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id),
  assigned_clinician_id uuid references public.profiles(id),
  revision integer not null check (revision > 0),
  status text not null check (status in ('draft','clinician_input_required','awaiting_review','manual_review','approved','withheld','needs_more_information','follow_up_required')),
  pathway text check (pathway in ('PATHWAY1','PATHWAY2')),
  routing_reason text,
  submitted_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now()
);
create table public.clinical_inputs (
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  revision integer not null,
  facts jsonb not null check (jsonb_typeof(facts) = 'object'),
  clinician_facts jsonb not null default '{}'::jsonb check (jsonb_typeof(clinician_facts) = 'object'),
  created_at timestamptz not null default now(),
  primary key (assessment_id,revision)
);
create table public.evaluations (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null,
  revision integer not null,
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  rule_version text not null,
  created_at timestamptz not null default now(),
  unique (assessment_id,revision),
  foreign key (assessment_id,revision) references public.clinical_inputs(assessment_id,revision)
);
create table public.clinician_decisions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments(id),
  revision integer not null,
  evaluation_id uuid not null references public.evaluations(id),
  clinician_id uuid not null references public.profiles(id),
  action text not null check (action in ('approved','withheld','needs_more_information','follow_up_required')),
  notes text not null check (length(notes) <= 10000),
  created_at timestamptz not null default clock_timestamp(),
  unique (assessment_id,revision)
);
create index assessments_patient_idx on public.assessments(patient_id);
create index assessments_queue_idx on public.assessments(status, submitted_at);

create function public.has_role(required_role text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid()
    and p.role = required_role and (p.role <> 'clinician' or p.approval_status = 'approved'));
$$;
create function public.can_review(case_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_role('clinician') and exists (select 1 from public.assessments a
    where a.id = case_id and a.status <> 'draft'
    and (a.assigned_clinician_id is null or a.assigned_clinician_id = auth.uid()));
$$;
create function public.owns_assessment(case_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_role('patient') and exists (select 1 from public.assessments a where a.id = case_id and a.patient_id = auth.uid());
$$;

alter table public.profiles enable row level security;
alter table public.assessments enable row level security;
alter table public.clinical_inputs enable row level security;
alter table public.evaluations enable row level security;
alter table public.clinician_decisions enable row level security;
create policy profile_read on public.profiles for select to authenticated using (
  id = auth.uid() or public.has_role('admin'));
create policy assessment_read on public.assessments for select to authenticated using (
  public.owns_assessment(id) or public.can_review(id));
create policy input_read on public.clinical_inputs for select to authenticated using (
  public.owns_assessment(assessment_id) or public.can_review(assessment_id));
create policy evaluation_read on public.evaluations for select to authenticated using (public.can_review(assessment_id));
create policy decision_read on public.clinician_decisions for select to authenticated using (
  public.owns_assessment(assessment_id) or public.can_review(assessment_id));

-- all writes use guarded operations; patients never select raw evaluations
revoke all on public.profiles, public.assessments, public.clinical_inputs, public.evaluations, public.clinician_decisions from anon, authenticated;
grant select on public.profiles, public.assessments, public.clinical_inputs, public.evaluations, public.clinician_decisions to authenticated;

create function public.provision_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare requested text := coalesce(new.raw_user_meta_data->>'role','patient');
begin
  if requested not in ('patient','clinician') then raise exception 'Public registration cannot grant this role'; end if;
  insert into public.profiles(id,full_name,email,role,approval_status,date_of_birth,sex_at_birth)
  values (new.id, trim(new.raw_user_meta_data->>'full_name'),coalesce(new.email,''),requested,
    case when requested = 'clinician' then 'pending' else null end,
    case when requested = 'patient' then nullif(new.raw_user_meta_data->>'date_of_birth','')::date else null end,
    case when requested = 'patient' then new.raw_user_meta_data->>'sex_at_birth' else null end);
  return new;
end $$;
create trigger provision_profile after insert on auth.users for each row execute function public.provision_profile();

create function public.review_clinician(p_id uuid, p_approval text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Not authorised' using errcode='42501'; end if;
  if p_approval not in ('approved','rejected') then raise exception 'Invalid approval'; end if;
  update public.profiles set approval_status=p_approval, reviewed_by=auth.uid(),reviewed_at=clock_timestamp()
  where id=p_id and role='clinician' and approval_status='pending';
  if not found then raise exception 'Account is no longer awaiting approval'; end if;
end $$;

create function public.get_assessment(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a public.assessments; e public.evaluations; d public.clinician_decisions; result jsonb;
begin
  select * into a from public.assessments where id=p_id;
  if not found or not (public.owns_assessment(p_id) or public.can_review(p_id)) then
    raise exception 'Assessment not available' using errcode='42501';
  end if;
  select * into e from public.evaluations where assessment_id=p_id and revision=a.revision;
  select * into d from public.clinician_decisions where assessment_id=p_id and revision=a.revision;
  result := to_jsonb(a) || jsonb_build_object(
    'patient_name',(select full_name from public.profiles where id=a.patient_id),
    'facts',(select facts from public.clinical_inputs where assessment_id=p_id and revision=a.revision),
    'decision_notes',d.notes, 'reviewed_at',d.created_at, 'reviewed_by',d.clinician_id);
  if public.can_review(p_id) then
    result := result || jsonb_build_object(
      'evaluation',e.result,
      'evaluation_id',e.id,
      'clinician_facts',(select clinician_facts from public.clinical_inputs where assessment_id=p_id and revision=a.revision));
  elsif a.status='approved' and d.action='approved' and d.evaluation_id=e.id then
    result := result || jsonb_build_object('approved_actions',e.result->'actions');
  end if;
  return result;
end $$;

create function public.list_assessments() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.get_assessment(a.id) order by a.updated_at desc),'[]'::jsonb)
  from public.assessments a where public.owns_assessment(a.id) or public.can_review(a.id);
$$;

create function public.save_assessment(p_id uuid, p_expected_revision integer, p_facts jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a public.assessments; new_revision integer; previous_clinician_facts jsonb := '{}'::jsonb;
begin
  if not public.has_role('patient') then raise exception 'Not authorised' using errcode='42501'; end if;
  if p_expected_revision is null or p_expected_revision<0 then raise exception 'Invalid revision'; end if;
  if jsonb_typeof(p_facts) is distinct from 'object' or octet_length(p_facts::text)>50000 then raise exception 'Invalid clinical input'; end if;
  p_facts := jsonb_strip_nulls(jsonb_build_object(
    'osteoporosisTreatmentStatus',p_facts->'osteoporosisTreatmentStatus',
    'age',(select to_jsonb(date_part('year',age(clock_timestamp(),p.date_of_birth))::integer) from public.profiles p where p.id=auth.uid() and p.date_of_birth is not null),
    'sex',p_facts->'sex',
    'postmenopausal',p_facts->'postmenopausal',
    'minimalTraumaFracture',p_facts->'minimalTraumaFracture',
    'fractureSite',p_facts->'fractureSite',
    'liveInResidentialCare',p_facts->'liveInResidentialCare'));
  -- serialise initial creation as well as updates for a stable client request id
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
  select * into a from public.assessments where id=p_id for update;
  if found then
    if a.patient_id <> auth.uid() then raise exception 'Not authorised' using errcode='42501'; end if;
    if a.revision=p_expected_revision+1 and exists (select 1 from public.clinical_inputs where assessment_id=p_id and revision=a.revision and facts=p_facts) then
      return public.get_assessment(p_id);
    end if;
    if a.revision is distinct from p_expected_revision or a.status <> 'draft' then raise exception 'Assessment changed. Reload before editing'; end if;
    select clinician_facts into previous_clinician_facts from public.clinical_inputs where assessment_id=p_id and revision=a.revision;
    new_revision := a.revision+1;
    update public.assessments set revision=new_revision,status='draft',pathway=null,routing_reason=null,updated_at=clock_timestamp() where id=p_id;
  else
    if p_expected_revision<>0 then raise exception 'Assessment no longer available'; end if;
    new_revision := 1;
    insert into public.assessments(id,patient_id,revision,status) values (p_id,auth.uid(),new_revision,'draft');
  end if;
  insert into public.clinical_inputs(assessment_id,revision,facts,clinician_facts) values (p_id,new_revision,p_facts,coalesce(previous_clinician_facts,'{}'::jsonb));
  return public.get_assessment(p_id);
end $$;

create function public.submit_pathway1_for_clinician_input(p_id uuid,p_revision integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a public.assessments; f jsonb;
begin
  if not public.has_role('patient') then raise exception 'Not authorised' using errcode='42501'; end if;
  select * into a from public.assessments where id=p_id for update;
  if not found or a.patient_id<>auth.uid() then raise exception 'Not authorised' using errcode='42501'; end if;
  if a.revision is distinct from p_revision or a.status<>'draft' then raise exception 'Assessment changed. Reload before submitting'; end if;
  select facts into f from public.clinical_inputs where assessment_id=p_id and revision=p_revision;
  if f->>'osteoporosisTreatmentStatus' = 'true' then raise exception 'Pathway 2 submission uses the evaluator boundary'; end if;
  update public.assessments
  set status='clinician_input_required',
      pathway='PATHWAY1',
      routing_reason='No previous or current osteoporosis treatment was recorded.',
      submitted_at=coalesce(submitted_at,clock_timestamp()),
      updated_at=clock_timestamp()
  where id=p_id;
  return public.get_assessment(p_id);
end $$;

create function public.save_pathway1_clinician_input(p_id uuid,p_revision integer,p_updated_at timestamptz,p_clinician_facts jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a public.assessments;
begin
  if not public.has_role('clinician') then raise exception 'Not authorised' using errcode='42501'; end if;
  if jsonb_typeof(p_clinician_facts) is distinct from 'object' or octet_length(p_clinician_facts::text)>50000 then raise exception 'Invalid clinical input'; end if;
  select * into a from public.assessments where id=p_id for update;
  if not found or not public.can_review(p_id) then raise exception 'Not authorised' using errcode='42501'; end if;
  if a.revision is distinct from p_revision or a.updated_at is distinct from p_updated_at or a.status<>'clinician_input_required' or a.pathway is distinct from 'PATHWAY1' then
    raise exception 'Assessment changed. Reload before entering clinical input';
  end if;
  update public.clinical_inputs set clinician_facts=p_clinician_facts where assessment_id=p_id and revision=p_revision;
  update public.assessments set assigned_clinician_id=auth.uid(),updated_at=clock_timestamp() where id=p_id;
  return public.get_assessment(p_id);
end $$;

-- only the verified edge function may persist an engine result
create function public.complete_evaluation(p_actor uuid,p_id uuid,p_revision integer,p_result jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.assessments; f jsonb; next_status text; existing_evaluation uuid;
begin
  select * into a from public.assessments where id=p_id for update;
  if not found then raise exception 'Not authorised' using errcode='42501'; end if;
  if a.revision is distinct from p_revision then raise exception 'Assessment changed'; end if;
  select facts into f from public.clinical_inputs where assessment_id=p_id and revision=p_revision;
  if not (
    (a.status='draft' and a.patient_id=p_actor and f->>'osteoporosisTreatmentStatus'='true'
      and exists(select 1 from public.profiles where id=p_actor and role='patient'))
    or
    (a.status='clinician_input_required' and exists(select 1 from public.profiles where id=p_actor and role='clinician' and approval_status='approved')
      and (a.assigned_clinician_id is null or a.assigned_clinician_id=p_actor))
  ) then raise exception 'Not authorised' using errcode='42501'; end if;
  if p_result->>'rule_version' is null or p_result->>'decision' not in ('action_taken','no_action','not_applicable','needs_more_information','not_integrated') then raise exception 'Invalid engine result'; end if;
  next_status := case
    when p_result->>'decision'='action_taken' then 'awaiting_review'
    when p_result->>'decision'='needs_more_information'
      and jsonb_array_length(coalesce(p_result->'missing_inputs','[]'::jsonb))>0
      and not exists (
        select 1 from jsonb_array_elements_text(coalesce(p_result->'missing_inputs','[]'::jsonb)) as missing(value)
        where missing.value not in ('eGFR','clinicalFrailtyScore','lifeExpectancy','knownPoorMedicationAdherence','cognitiveImpairment','testAvailable','testWithinLast2Years','T-score','hipVertebralOrMultipleFracturesInLast24M','highRisk','yearSincePostmenopausal','isRobustWoman'))
      then 'clinician_input_required'
    else 'manual_review'
  end;
  select id into existing_evaluation from public.evaluations where assessment_id=p_id and revision=p_revision;
  if existing_evaluation is null then
    insert into public.evaluations(assessment_id,revision,result,rule_version) values (p_id,p_revision,p_result,p_result->>'rule_version');
  else
    update public.evaluations set result=p_result,rule_version=p_result->>'rule_version',created_at=clock_timestamp() where id=existing_evaluation;
  end if;
  update public.assessments set status=next_status,pathway=p_result->>'pathway',routing_reason=p_result->>'routing_reason',submitted_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_id;
end $$;

create function public.record_decision(p_id uuid,p_revision integer,p_updated_at timestamptz,p_evaluation_id uuid,p_action text,p_notes text) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.assessments; e public.evaluations;
begin
  select * into a from public.assessments where id=p_id for update;
  if not found or not public.can_review(p_id) then raise exception 'Not authorised' using errcode='42501'; end if;
  if a.revision is distinct from p_revision or a.updated_at is distinct from p_updated_at or a.status not in ('awaiting_review','manual_review') then raise exception 'Assessment changed. Reload before deciding'; end if;
  select * into e from public.evaluations where id=p_evaluation_id and assessment_id=p_id and revision=p_revision;
  if not found then raise exception 'Evaluation changed'; end if;
  if p_action not in ('approved','withheld','needs_more_information','follow_up_required') then raise exception 'Invalid decision'; end if;
  if length(trim(coalesce(p_notes,'')))=0 then raise exception 'Decision notes are required'; end if;
  if p_action='approved' and (a.pathway is distinct from 'PATHWAY1' or e.result->>'decision' is distinct from 'action_taken'
    or jsonb_array_length(coalesce(e.result->'missing_inputs','[]'))>0 or jsonb_array_length(coalesce(e.result->'actions','[]'))=0) then raise exception 'This evaluation cannot be approved'; end if;
  insert into public.clinician_decisions(assessment_id,revision,evaluation_id,clinician_id,action,notes) values(p_id,p_revision,p_evaluation_id,auth.uid(),p_action,trim(p_notes));
  update public.assessments set status=p_action,assigned_clinician_id=auth.uid(),updated_at=clock_timestamp() where id=p_id;
end $$;

revoke all on function public.has_role(text),public.can_review(uuid),public.owns_assessment(uuid),public.provision_profile(),public.review_clinician(uuid,text),public.get_assessment(uuid),public.list_assessments(),public.save_assessment(uuid,integer,jsonb),public.submit_pathway1_for_clinician_input(uuid,integer),public.save_pathway1_clinician_input(uuid,integer,timestamptz,jsonb),public.complete_evaluation(uuid,uuid,integer,jsonb),public.record_decision(uuid,integer,timestamptz,uuid,text,text) from public,anon,authenticated;
grant execute on function public.has_role(text),public.can_review(uuid),public.owns_assessment(uuid),public.review_clinician(uuid,text),public.get_assessment(uuid),public.list_assessments(),public.save_assessment(uuid,integer,jsonb),public.submit_pathway1_for_clinician_input(uuid,integer),public.save_pathway1_clinician_input(uuid,integer,timestamptz,jsonb),public.record_decision(uuid,integer,timestamptz,uuid,text,text) to authenticated;
grant execute on function public.complete_evaluation(uuid,uuid,integer,jsonb) to service_role;
commit;
