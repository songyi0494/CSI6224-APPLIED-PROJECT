create or replace function public.review_clinical_case_results(
    p_case_id uuid,
    p_expected_investigation_revision integer,
    p_expected_questionnaire_revision integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
    v_investigation public.investigations%rowtype;
    v_date_of_birth date;
    v_answers jsonb;
    v_questionnaire_revision integer;
    v_questionnaire_status text;
    v_dietary_dairy_servings numeric;
    v_age integer;
    v_older_people boolean;
    v_vitamin_d_recommendation text;
    v_vitamin_d_recheck boolean;
    v_hypocalcaemia boolean;
    v_calcium_supplement_required boolean;
    v_calcium_recommendation text;
    v_protein_min_grams numeric;
    v_protein_max_grams numeric;
    v_protein_recommendation text;
    v_result jsonb;
    v_lifestyle_advice jsonb := '[]'::jsonb;
begin
    if auth.uid() is null or not public.is_approved_clinician() then
        raise exception 'Only approved clinicians can review clinical case results'
        using errcode = '42501';
    end if;

    select * into v_case
    from public.clinical_cases
    where id = p_case_id
    for update;

    if not found then
        raise exception 'Clinical case not found';
    end if;
    if v_case.assigned_clinician_id is distinct from auth.uid() then
        raise exception 'You can only review your assigned clinical case'
        using errcode = '42501';
    end if;
    if v_case.status not in ('in_progress', 'evaluated') then
        raise exception 'Only current in-progress or evaluated cases can be reviewed';
    end if;
    if v_case.status = 'evaluated' and (
        v_case.rule_evaluation is null
        or (v_case.rule_evaluation ->> 'status') is distinct from 'complete'
        or (v_case.rule_evaluation ->> 'pathwayRevision')::integer
            is distinct from v_case.pathway_revision
    ) then
    raise exception 'A current terminal evaluation is required for results review';
    end if;

    select answers, revision, status
    into v_answers, v_questionnaire_revision, v_questionnaire_status
    from public.questionnaire_responses
    where id = v_case.questionnaire_response_id;

    if not found or v_questionnaire_status <> 'submitted' then
        raise exception 'A submitted questionnaire response is required';
    end if;
    if v_questionnaire_revision is distinct from p_expected_questionnaire_revision then
         raise exception 'Questionnaire response changed. Reload before generating advice';
    end if;

    select * into v_investigation
    from public.investigations
    where case_id = p_case_id
    for update;

    if not found
        or v_investigation.revision is distinct from p_expected_investigation_revision
        or not public.phase3ca_investigations_complete(p_case_id)
    then
        raise exception 'Current complete investigations are required for results review';
    end if;
    if v_case.status = 'evaluated'
        and (v_case.rule_evaluation ->> 'investigationRevision')::integer
        is distinct from v_investigation.revision
    then
        raise exception 'The terminal evaluation is stale for current Investigations';
    end if;

    select date_of_birth into v_date_of_birth
    from public.profiles
    where id = v_case.patient_id;

    if v_date_of_birth is null or v_date_of_birth > current_date then
        raise exception 'A valid patient date of birth is required for results review';
    end if;

    begin
        v_dietary_dairy_servings := nullif(v_answers ->> 'dietaryDairyServings', '')::numeric;
    exception when others then
        raise exception 'Dietary dairy servings is invalid for results review';
    end;

    if v_dietary_dairy_servings is null
        or v_dietary_dairy_servings < 0
        or v_dietary_dairy_servings::text in ('NaN', 'Infinity', '-Infinity')
    then
        raise exception 'Dietary dairy servings is required for results review';
    end if;

    v_age := extract(year from age(current_date, v_date_of_birth))::integer;
    v_older_people := v_age >= 65;

    if v_investigation.vitamin_d_level < 40 then
        v_vitamin_d_recommendation :=
            'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily';
        v_vitamin_d_recheck := v_investigation.vitamin_d_level < 25;
    elsif v_investigation.vitamin_d_level between 40 and 75 then
        v_vitamin_d_recommendation := 'Cholecalciferol 25 microg daily ongoing';
        v_vitamin_d_recheck := false;
    else
        v_vitamin_d_recommendation := null;
        v_vitamin_d_recheck := false;
    end if;

    v_hypocalcaemia := v_investigation.ionised_calcium < 1.12;
    v_calcium_supplement_required :=
        v_dietary_dairy_servings < 3 or v_hypocalcaemia;
    if v_calcium_supplement_required then
        v_calcium_recommendation := 'Calcium supplement 600 mg daily';
    else
        v_calcium_recommendation := null;
    end if;

    if v_older_people then
        v_protein_min_grams := v_investigation.body_weight_kg * 1.0;
        v_protein_max_grams := v_investigation.body_weight_kg * 1.2;
        v_protein_recommendation :=
            'Protein target: 1.0-1.2 g/kg bodyweight daily';
    else
        v_protein_min_grams := null;
        v_protein_max_grams := null;
        v_protein_recommendation := null;
    end if;

    -- Questionnaire choices are Yes/No. Also accept equivalent boolean JSON.
    -- No, missing and unknown answers do not generate cessation/reduction advice.
    if lower(btrim(coalesce(v_answers ->> 'smoking', ''))) in ('yes', 'true') then
        v_lifestyle_advice := v_lifestyle_advice
            || jsonb_build_array('Ceasing smoking');
    end if;

    if lower(btrim(coalesce(v_answers ->> 'alcohol', ''))) in ('yes', 'true') then
        v_lifestyle_advice := v_lifestyle_advice
            || jsonb_build_array('Reducing alcohol intake');
    end if;

    v_lifestyle_advice := v_lifestyle_advice
      || jsonb_build_array('Weight bearing exercises');

    v_result := jsonb_build_object(
        'vitaminD', jsonb_build_object(
        'level', v_investigation.vitamin_d_level,
        'unit', 'nmol/L',
        'recommendation', v_vitamin_d_recommendation,
        'recheckBeforeTreatment', v_vitamin_d_recheck
        ),
        'calcium', jsonb_build_object(
        'totalCalcium', v_investigation.total_calcium,
        'ionisedCalcium', v_investigation.ionised_calcium,
        'ionisedCalciumUnit', 'mmol/L',
        'hypocalcaemia', v_hypocalcaemia,
        'supplementRequired', v_calcium_supplement_required,
        'recommendation', v_calcium_recommendation
        ),
        'protein', jsonb_build_object(
        'age', v_age,
        'ageAsOf', current_date,
        'olderPeople', v_older_people,
        'bodyWeightKg', v_investigation.body_weight_kg,
        'bodyWeightUnit', 'kg',
        'minimumGramsPerDay', v_protein_min_grams,
        'maximumGramsPerDay', v_protein_max_grams,
        'recommendation', v_protein_recommendation
        ),
        'lifestyleAdvice', v_lifestyle_advice,
        'source', jsonb_build_object(
        'investigationRevision', v_investigation.revision,
        'questionnaireRevision', v_questionnaire_revision,
        'generatedAt', now(),
        'generatedBy', auth.uid()
      )
    );

    update public.clinical_cases
    set results_review = v_result,
        updated_at = now()
    where id = p_case_id;

    return v_result;
end;
$$;


revoke all on function public.review_clinical_case_results(uuid, integer, integer)
from public, anon;
grant execute on function public.review_clinical_case_results(uuid, integer, integer)
to authenticated;
