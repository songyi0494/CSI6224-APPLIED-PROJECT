alter table public.clinical_cases
add column pathway_answer_order text[] not null default '{}';

create or replace function public.save_pathway_answer(
    p_case_id uuid,
    p_field_key text,
    p_value jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
    v_updated_facts jsonb;
    v_updated_order text[];
    v_existing_position integer;
    v_downstream_key text;
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

    v_updated_facts :=
        coalesce(v_case.clinician_facts, '{}'::jsonb);
    v_updated_order :=
        coalesce(v_case.pathway_answer_order, '{}'::text[]);
    v_existing_position :=
        array_position(v_updated_order, p_field_key);

    if v_existing_position is not null
        and v_updated_facts -> p_field_key = p_value then
        return v_updated_facts;
    end if;

    if cardinality(v_updated_order) = 0 then
        v_updated_facts := '{}'::jsonb;
        v_updated_order := array[p_field_key];

    elsif v_existing_position is not null then
        if v_existing_position < cardinality(v_updated_order) then
            foreach v_downstream_key in array
                v_updated_order[
                    (v_existing_position + 1):
                    cardinality(v_updated_order)
                ]
            loop
                v_updated_facts :=
                    v_updated_facts - v_downstream_key;
            end loop;
        end if;

        v_updated_order :=
            v_updated_order[1:v_existing_position];

    else
        v_updated_order :=
            array_append(v_updated_order, p_field_key);
    end if;

    v_updated_facts := jsonb_set(
        v_updated_facts,
        array[p_field_key],
        p_value,
        true
    );

    update public.clinical_cases
    set
        clinician_facts = v_updated_facts,
        pathway_answer_order = v_updated_order,
        pathway_revision = pathway_revision + 1,
        rule_evaluation = null,
        pathway = null,
        routing_reason = null,
        updated_at = now()
    where id = p_case_id
    returning clinician_facts into v_updated_facts;

    return v_updated_facts;
end;
$$;

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
        'pathway_answer_order', v_case.pathway_answer_order,
        'assigned_clinician_id', v_case.assigned_clinician_id,
        'status', v_case.status,
        'pathway_revision', v_case.pathway_revision
    );
end;
$$;
