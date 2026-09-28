create or replace function public.save_rule_evaluation (
    p_case_id uuid,
    p_evaluation jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare 
    v_case public.clinical_cases%rowtype;
    v_pathway text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can save pathway evaluations';
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
        raise exception 'You can only evaluate your assigned clinical case';
    end if;

    if v_case.status <> 'in_progress' then
        raise exception 'Only in-progress clinical cases can be evaluated';
    end if;

    if (p_evaluation ->> 'status') is distinct from 'complete' then
        raise exception 'Only completed pathway evaluations can be saved';
    end if;

    v_pathway := p_evaluation ->> 'pathwayId';

    if v_pathway is null
        or v_pathway not in ('PATHWAY1', 'PATHWAY2') then
        raise exception 'Invalid pathway evaluation result';
    end if;

    if jsonb_typeof(p_evaluation -> 'actions') is distinct from 'array' then
        raise exception 'Evaluation actions must be an array';
    end if;

    if jsonb_typeof(p_evaluation -> 'trace') is distinct from 'array' then
        raise exception 'Evaluation trace must be an array';
    end if;

    update public.clinical_cases
    set
        rule_evaluation =
            p_evaluation
            || jsonb_build_object(
                'pathwayRevision', v_case.pathway_revision,
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


revoke all
on function public.save_rule_evaluation(uuid, jsonb)
from public, anon;

grant execute
on function public.save_rule_evaluation(uuid, jsonb)
to authenticated;