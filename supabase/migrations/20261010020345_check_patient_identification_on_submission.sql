create or replace function public.submit_questionnaire_response(
    p_response_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_response public.questionnaire_responses%rowtype;
    v_case_id uuid;
    v_profile_gender text;
    v_date_of_birth date;
    v_age integer;
    v_eligible boolean;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if public.current_user_role() is distinct from 'patient' then
        raise exception 'Only patients can submit questionnaire responses';
    end if;

    select *
    into v_response
    from public.questionnaire_responses
    where id = p_response_id
    for update;

    if not found then
        raise exception 'Questionnaire response not found';
    end if;

    if v_response.patient_id is distinct from auth.uid() then
        raise exception 'You can only submit your own questionnaire response';
    end if;

    if v_response.status <> 'draft' then
        raise exception 'Questionnaire response has already been submitted';
    end if;

    -- Get patient profile information
    select lower(btrim(p.gender)), p.date_of_birth
    into v_profile_gender, v_date_of_birth
    from public.profiles as p
    where p.id = auth.uid();

    if v_profile_gender is null
        or v_profile_gender not in (
            'female', 'male', 'another term', 'another_term', 'other'
        ) then
        raise exception 'Sex recorded at birth is unavailable in your profile';
    end if;

    if v_date_of_birth is null
        or v_date_of_birth > current_date then
        raise exception 'Valid date of birth is required';
    end if;

    -- Existing required-question validation
    if exists (
        select 1
        from public.questionnaire_questions as q
        where q.is_required = true
          and (
              q.field_key is distinct from 'postmenopausal'
              or v_profile_gender = 'female'
          )
          and (
              not (
                  v_response.answers
                  ? coalesce(q.field_key, q.id::text)
              )
              or v_response.answers
                  -> coalesce(q.field_key, q.id::text)
                  = 'null'::jsonb
          )
    ) then
        raise exception 'All required questionnaire questions must be answered';
    end if;

    -- Q2 is required only when Q1 = Yes
    if lower(btrim(v_response.answers ->> 'minimalTraumaFracture')) = 'yes'
       and coalesce(
           lower(btrim(v_response.answers ->> 'excludedFractureSite')),
           ''
       ) not in ('yes', 'no') then
        raise exception
            'Please specify whether the fracture was in an excluded site';
    end if;

    -- Calculate age
    v_age := extract(
        year from age(current_date, v_date_of_birth)
    )::integer;

    -- Patient Identification eligibility
    v_eligible := (
        (
            (
                v_profile_gender = 'female'
                and lower(btrim(
                    v_response.answers ->> 'postmenopausal'
                )) = 'yes'
            )
            or
            (
                v_profile_gender = 'male'
                and v_age > 50
            )
        )
        and lower(btrim(
            v_response.answers ->> 'minimalTraumaFracture'
        )) = 'yes'
        and lower(btrim(
            v_response.answers ->> 'excludedFractureSite'
        )) = 'no'
    );

    -- All patients can submit their questionnaire
    update public.questionnaire_responses
    set
        status = 'submitted',
        submitted_at = now()
    where id = p_response_id;

    -- Not eligible: do not create a clinical case
    if not coalesce(v_eligible, false) then
        return null;
    end if;

    -- Eligible: continue the existing workflow
    insert into public.clinical_cases (
        patient_id,
        questionnaire_response_id,
        status,
        submitted_at
    )
    values (
        auth.uid(),
        p_response_id,
        'clinician_input_required',
        now()
    )
    returning id into v_case_id;

    return v_case_id;
end;
$$;