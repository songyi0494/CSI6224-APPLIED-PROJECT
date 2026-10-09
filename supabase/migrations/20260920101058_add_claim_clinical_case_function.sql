create or replace function public.claim_clinical_case(p_case_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from public.profiles
        where id = auth.id()
            and role = 'clinician'
    ) then
        raise exception 'Only clinincians can claim clinical cases';
    end if;

    update public.clinical_cases
    set 
        assigned_clinician_id = auth.id(),
        status = 'in_progress',
        claimed_at = now(),
        updated_at = now()
    where id = p_case_id
        and status = 'clinician_input_required'
        and assigned_clinician_id is null;
    
    if not found then 
        raise exception 'Clinical case is not available for claim';
    end if;
end;
$$;

revoke execute on function public.claim_clinical_case(uuid)
from public;

grant execute on function public.claim_clinical_case(uuid)
to authenticated;