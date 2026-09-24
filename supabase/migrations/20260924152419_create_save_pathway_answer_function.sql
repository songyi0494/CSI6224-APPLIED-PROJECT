create or replace function public.save_pathway_answer(
    p_case_id uuid,
    p_field_key text,
    p_value jsonb
)
return jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_case%rowtype;
    v_updated_facts jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    
    if not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can save pathway answers';
    end if;

    if p_field_key is null or btrim(p_field_key) = '' then
        raise exception 'Pathway answer field key is required';
    end if;

    if p_value is null or p_value = 'null'::jsonb then
        raise exception 'Pathway answer value is required';
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
        raise exception 'You can only update your assigned clinical case';
    end if;

     if v_case.status <> 'in_progress' then
        raise exception 'Only in-progress clinical cases can receive pathway answers';
    end if;

    -- Pathway can start only after investigations and Results Review
    if not exists (
        select 1
        from public.investigations as i
        where i.case_id = p_case_id
          and i.completed_at is not null
    ) then
        raise exception 'Investigations must be completed before starting the pathway';
    end if;

    update public.clinical_cases
    set
        clinician_facts = jsonb_set(
            coalesce(clinician_facts, '{}'::jsonb),
            array[p_field_key],
            p_value,
            true
        ),
        revision = revision + 1,
        updated_at = now()
    where id = p_case_id
    returning clinician_facts into v_updated_facts;

    return v_updated_facts;
end;;
$$;

revoke all on function public.save_pathway_answer(uuid, text, jsonb)
from public, anon;

grant execute on function public.save_pathway_answer(uuid, text, jsonb)
to authenticated

revoke update(clinician_facts) on public.clinical_cases
from authenticated;