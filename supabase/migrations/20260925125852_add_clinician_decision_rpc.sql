create or replace function public.review_pathway_evaluation(
    p_case_id uuid,
    p_decision text,
    p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can review pathway evaluations';
    end if;

    if p_decision not in ('approved', 'rejected') then
        raise exception 'Decision must be approved or rejected';
    end if;

    select *
    into v_case
    from public.clinical_cases
    where id = p_case_id
    for update;

    if not found then
        raise exception 'Clinical case not found';
    end if;

    if v_case.assigned_clinician_id is distinct from auth.uid() then
        raise exception 'You can only review your assigned clinical case';
    end if;

    if v_case.status <> 'evaluated' then
        raise exception 'Only evaluated clinical cases can be reviewed';
    end if;

    if v_case.rule_evaluation is null then
        raise exception 'Pathway evaluation result not found';
    end if;

    if not (v_case.rule_evaluation ? 'pathwayRevision') then
        raise exception 'Pathway evaluation revision not found';
    end if;

    if (v_case.rule_evaluation ->> 'pathwayRevision')::integer
        is distinct from v_case.pathway_revision then
        raise exception 'Pathway evaluation is out of date';
    end if;

    insert into public.clinician_decisions (
        case_id,
        clinician_id,
        decision,
        notes,
        pathway_revision
    )
    values (
        p_case_id,
        auth.uid(),
        p_decision,
        nullif(btrim(p_notes), ''),
        v_case.pathway_revision
    )
    on conflict (case_id)
    do update set
        clinician_id = excluded.clinician_id,
        decision = excluded.decision,
        notes = excluded.notes,
        pathway_revision = excluded.pathway_revision,
        updated_at = now();
    
    if p_decision = 'rejected' then
        update public.clinical_cases
        set 
            status = 'in_progress',
            updated_at = now()
        where id = p_case_id;
    end if;
end;
$$;