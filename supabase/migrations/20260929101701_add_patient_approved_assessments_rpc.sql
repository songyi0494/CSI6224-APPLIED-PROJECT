create or replace function public.get_my_approved_assessments()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_results jsonb;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    if public.current_user_role() is distinct from 'patient' then
        raise exception 'Only patients can view their approved assessments';
    end if;

        select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'caseId', c.id,
                'submittedAt', c.submitted_at,
                'reviewedAt', d.updated_at,
                'pathway', c.pathway,
                'resultsReview', c.results_review,
                'careRecommendation',
                    coalesce(
                        c.rule_evaluation -> 'actions',
                        '[]'::jsonb
                    ),
                'clinicianMessage', d.notes
            )
            order by d.updated_at desc
        ),
        '[]'::jsonb
    )
    into v_results
    from public.clinical_cases as c
    join public.clinician_decisions as d
        on d.case_id = c.id
    where c.patient_id = auth.uid()
        and c.status = 'evaluated'
        and c.rule_evaluation is not null
        and d.decision = 'approved'
        and d.clinician_id = c.assigned_clinician_id
        and d.pathway_revision = c.pathway_revision;
    
    return v_results;
end;
$$;

revoke all
on function public.get_my_approved_assessments()
from public, anon;

grant execute
on function public.get_my_approved_assessments()
to authenticated;
