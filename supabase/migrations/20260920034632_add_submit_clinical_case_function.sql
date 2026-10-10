create or replace function public.submit_clinical_case(p_case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
    v_treatment_status text;
    v_pathway text;
    v_routing_reason text;
begin
    select *
    into v_case
    from public.clinical_cases
    where id = p_case_id;

    if not found then 
        raise exception 'Clinical case not found';
    end if;
    
    if v_case.patient_id <> auth.uid() then
        raise exception 'You can only submit your own clinical case';
    end if;

    if v_case.status <> 'draft' then
        raise exception 'Only draft clinical cases can be submitted';
    end if;

    v_treatment_status :=
        v_case.patient_facts ->> 'osteoporosisTreatmentStatus';
    
    if v_treatment_status is null then
        raise exception 'Osteoporosis treatment status is required';
    end if;

    if v_treatment_status = 'no' then
        v_pathway := 'PATHWAY1';
        v_routing_reason := 'No previous or current osteoporosis treatment was recorded';
    elsif v_treatment_status = 'yes' then
        v_pathway := 'PATHWAY2';
        v_routing_reason := 'Previous or current osteoporosis treatment was recorded';
    elsif v_treatment_status = 'not_sure' then
        v_pathway := null;
        v_routing_reason := 'Treatment status is uncertain and requires clinician review';
    else
        raise exception 'Invalid osteoporosis treatment status';
    end if;

    update public.clinical_cases
    set 
        pathway = v_pathway,
        routing_reason = v_routing_reason,
        status = 'clinician_input_required',
        submitted_at = now()
    where id = p_case_id;

end;
$$;

revoke execute on function public.submit_clinical_case(uuid)
from public;

grant execute on function public.submit_clinical_case(uuid)
to authenticated;