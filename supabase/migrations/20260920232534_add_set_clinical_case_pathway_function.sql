create or replace function public.set_clinical_case_pathway (
    p_case_id uuid,
    p_pathway text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from puglic.profiles
        where id = auth.uid()
            and role = 'clinician'
    ) then
        raise exception 'Only clinicians can set clinical case pathway';
    end if;

    if p_pathway not in ('PATHWAY1', 'PATHWAY2') then
        raise exception 'Invalid pathway';
    end if;

    update public.clinical_cases
    set
        pathway = p_pathway,
        routing_reason = 'Pathway selected by clinician after treatment status review',
        updated_at = now()
    where id = p_case_id
        and assigned_clinician_id = auth.uid()
        and status = 'in_progress'
        and pathway is null;
    
    if not found then
        raise exception 'Clinical case is not available for pathway selection';
    end if;
end;
$$;

revoke execute on function public.set_clinical_case_pathway(uuid, text)
from public;

grant execute on function public.set_clinical_case_pathway(uuid, text)
to authenticated;