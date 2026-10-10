create or replace function public.check_pathway_eligibility(
    p_case_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_gender text;
    v_date_of_birth date;
    v_answers jsonb;
    v_age integer;
begin
    select
        lower(btrim(p.gender)),
        p.date_of_birth,
        qr.answers
    into
        v_gender,
        v_date_of_birth,
        v_answers
    from public.clinical_cases cc
    join public.profiles p
        on p.id = cc.patient_id
    join public.questionnaire_responses qr
        on qr.id = cc.questionnaire_response_id
       and qr.patient_id = cc.patient_id
    where cc.id = p_case_id
      and qr.status = 'submitted';

    if not found or v_date_of_birth is null then
        return false;
    end if;

    v_age := extract(
        year from age(current_date, v_date_of_birth)
    )::integer;

    return coalesce(
        (
            (
                v_gender = 'female'
                and lower(btrim(v_answers ->> 'postmenopausal')) = 'yes'
            )
            or
            (
                v_gender = 'male'
                and v_age > 50
            )
        )
        and lower(btrim(v_answers ->> 'minimalTraumaFracture')) = 'yes'
        and lower(btrim(v_answers ->> 'excludedFractureSite')) = 'no',
        false
    );
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
    v_investigation_revision integer;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can evaluate pathways'
            using errcode = '42501';
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

    if not public.check_pathway_eligibility(p_case_id) then
        raise exception
            'Patient does not meet the pathway entry criteria';
    end if;

    if not public.phase3ca_investigations_complete(p_case_id) then
        raise exception
            'Current complete investigations are required before evaluating the pathway';
    end if;

    select revision
    into v_investigation_revision
    from public.investigations
    where case_id = p_case_id;

    return jsonb_build_object(
        'id', v_case.id,
        'clinician_facts', v_case.clinician_facts,
        'pathway_answer_order', v_case.pathway_answer_order,
        'assigned_clinician_id', v_case.assigned_clinician_id,
        'status', v_case.status,
        'pathway_revision', v_case.pathway_revision,
        'investigation_revision', v_investigation_revision
    );
end;
$$;