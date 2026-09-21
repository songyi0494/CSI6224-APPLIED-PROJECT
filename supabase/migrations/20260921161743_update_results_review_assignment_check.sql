create or replace function public.review_clinical_case_results(
    p_case_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
    v_date_of_birth date;

    v_dietary_dairy_servings numeric;
    v_vitamin_d_level numeric;
    v_total_calcium numeric;
    v_ionised_calcium numeric;
    v_body_weight_kg numeric;

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
begin
    select *
    into v_case
    from public.clinical_cases
    where id = p_case_id;

    if not found then
        raise exception 'Clinical case not found';
    end if;

    if not exists (
        select 1
        from public.profiles
        where id = auth.uid()
            and role = 'clinician'
    ) then
        raise exception 'Only clinicians can review clinical case results';
    end if;

    if v_case.assigned_clinician_id is distinct from auth.uid() then
        raise exception 'You can only review your assigned clinical case';
    end if;

    if v_case.status <> 'in_progress' then
        raise exception 'Only in-progress clinical cases can be reviewed';
    end if;

    select date_of_birth
    into v_date_of_birth
    from public.profiles
    where id = v_case.patient_id;

    if v_date_of_birth is null then
        raise exception 'Patient date of birth is required for results review';
    end if;

    v_dietary_dairy_servings :=
        (v_case.patient_facts ->> 'dietaryDairyServings')::numeric;
    if v_dietary_dairy_servings is null then
        raise exception 'Dietary dairy servings is required for results review';
    end if;
    v_vitamin_d_level :=
        (v_case.clinician_facts ->> 'vitaminDLevel')::numeric;
    if v_vitamin_d_level is null then
        raise exception 'Vitamin D level is required for results review';
    end if;
    v_total_calcium :=
        (v_case.clinician_facts ->> 'totalCalcium')::numeric;
    v_ionised_calcium :=
        (v_case.clinician_facts ->> 'ionisedCalcium')::numeric;
    if v_ionised_calcium is null then
        raise exception 'Ionised calcium is required for results review';
    end if;
    v_body_weight_kg :=
        (v_case.clinician_facts ->> 'bodyWeightKg')::numeric; 

    v_age :=
        extract(year from age(current_date, v_date_of_birth));
    v_older_people :=
        v_age >= 65;
    if v_older_people and v_body_weight_kg is null then
        raise exception 'Body weight is required for protein recommendation in older patients';
    end if;

    --VitaminDLevel
    if v_vitamin_d_level < 40 then

        v_vitamin_d_recommendation :=
            'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily';

        v_vitamin_d_recheck :=
            v_vitamin_d_level < 25;

    elsif v_vitamin_d_level between 40 and 75 then

        v_vitamin_d_recommendation :=
            'Cholecalciferol 25 microg daily ongoing';

        v_vitamin_d_recheck := false;

    else
        v_vitamin_d_recommendation := null;
        v_vitamin_d_recheck := false;
    end if;

    --Calcium
    v_hypocalcaemia :=
        v_ionised_calcium < 1.12;
    v_calcium_supplement_required :=
        v_dietary_dairy_servings <3
        or v_hypocalcaemia;
    if v_calcium_supplement_required then
        v_calcium_recommendation :=
        'Calcium supplement 600 mg daily';
    else
        v_calcium_recommendation := null;
    end if;

    --Protein
    if v_older_people then
        v_protein_min_grams :=
            v_body_weight_kg * 1.0;
        v_protein_max_grams :=
            v_body_weight_kg * 1.2;
        v_protein_recommendation :=
            'Protein target: 1.0-1.2 g/kg bodyweight daily';
    else
        v_protein_min_grams := null;
        v_protein_max_grams := null;
        v_protein_recommendation := null;
    end if;

    --Save results_review json file to DB
    update public.clinical_cases
    set
        results_review = jsonb_build_object(
            'vitaminD',
            jsonb_build_object(
                'level', v_vitamin_d_level,
                'recommendation', v_vitamin_d_recommendation,
                'recheckBeforeTreatment', v_vitamin_d_recheck
            ),

            'calcium',
            jsonb_build_object(
                'totalCalcium', v_total_calcium,
                'ionisedCalcium', v_ionised_calcium,
                'hypocalcaemia', v_hypocalcaemia,
                'supplementRequired', v_calcium_supplement_required,
                'recommendation', v_calcium_recommendation
            ),

            'protein',
            jsonb_build_object(
                'age', v_age,
                'olderPeople', v_older_people,
                'bodyWeightKg', v_body_weight_kg,
                'minimumGramsPerDay', v_protein_min_grams,
                'maximumGramsPerDay', v_protein_max_grams,
                'recommendation', v_protein_recommendation
            ),

            'lifestyleAdvice',
            jsonb_build_array(
                'Ceasing smoking',
                'Reducing alcohol intake',
                'Weight bearing exercises'
            )
        ),
        updated_at = now()
    where id = p_case_id;
end;
$$;

revoke execute on function public.review_clinical_case_results(uuid)
from public;

grant execute on function public.review_clinical_case_results(uuid)
to authenticated;