revoke all on function public.review_pathway_evaluation(uuid, text, text)
from public, anon;

grant execute on function public.review_pathway_evaluation(uuid, text, text)
to authenticated;

alter table public.clinician_decisions
enable row level security;

revoke all on table public.clinician_decisions
from anon, authenticated;

grant select on table public.clinician_decisions
to authenticated;

create policy "Assigned clinician can view clinical decisions"
on public.clinician_decisions
for select
to authenticated
using (
    public.is_approved_clinician()
    and exists (
        select 1
        from public.clinical_cases as c
        where c.id = clinician_decisions.case_id
            and c.assigned_clinician_id = auth.uid()
    )
);

create policy "Admin can view clinical decisions"
on public.clinician_decisions
for select
to authenticated
using (
    public.is_admin()
);

revoke select
on table public.clinical_cases
from authenticated;

grant select (
    id,
    patient_id,
    assigned_clinician_id,
    clinician_facts,
    pathway,
    routing_reason,
    status,
    submitted_at,
    claimed_at,
    created_at,
    updated_at,
    results_review,
    questionnaire_response_id,
    pathway_revision
)
on table public.clinical_cases
to authenticated;

create or replace function public.get_rule_evaluation(
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

    select *
    into v_case
    from public.clinical_cases
    where id = p_case_id;

    if not found then
        raise exception 'Clinical case not found';
    end if;

    if v_case.rule_evaluation is null then
        raise exception 'Rule evaluation not found';
    end if;

    if public.is_admin() then
        return v_case.rule_evaluation;
    end if;

    if public.is_approved_clinician()
        and v_case.assigned_clinician_id = auth.uid() then
        return v_case.rule_evaluation;
    end if;

    if v_case.patient_id = auth.uid()
        and v_case.status = 'evaluated'
        and exists (
            select 1
            from public.clinician_decisions as d 
            where d.case_id = p_case_id
                and d.decision = 'approved'
                and d.clinician_id = v_case.assigned_clinician_id
                and d.pathway_revision = v_case.pathway_revision
        ) then
        return v_case.rule_evaluation;
    end if;

    raise exception 'You do not have permission to view this rule evaluation';
end;
$$;

revoke all on function public.get_rule_evaluation(uuid)
from public, anon;

grant execute on function public.get_rule_evaluation(uuid)
to authenticated;