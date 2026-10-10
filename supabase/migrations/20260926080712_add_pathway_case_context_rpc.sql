create or replace function public.get_pathway_case_context(
    p_case_id uuid
)
returns jsonb
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
        raise exception 'Only approved clinicians can evaluate pathways';
    end if;

    select *
    into v_case
    from public.clinical_cases
    where id = p_case_id;

    if not found then
        raise exception 'Clinical case not found';
    end if;

    if v_case.assigned_clinician_id is distinct from auth.uid() then
        raise exception 'You can only evaluate your assigned clinical case';
    end if;

    if v_case.status <> 'in_progress' then
        raise exception 'Only in-progress clinical cases can be evaluated';
    end if;

    return jsonb_build_object(
        'id', v_case.id,
        'clinician_facts', v_case.clinician_facts,
        'assigned_clinician_id', v_case.assigned_clinician_id,
        'status', v_case.status,
        'pathway_revision', v_case.pathway_revision
    );
end;
$$;

revoke all on function public.get_pathway_case_context(uuid)
from public, anon;

grant execute on function public.get_pathway_case_context(uuid)
to authenticated;