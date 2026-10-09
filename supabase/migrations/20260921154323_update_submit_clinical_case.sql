create or replace function public.submit_clinical_case(p_case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_case public.clinical_cases%rowtype;
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

    update public.clinical_cases
    set 
        status = 'clinician_input_required',
        submitted_at = now(),
        updated_at = now()
    where id = p_case_id;

end;
$$;

revoke execute on function public.submit_clinical_case(uuid)
from public;

grant execute on function public.submit_clinical_case(uuid)
to authenticated;