create or replace function public.save_rule_evaluation(
    p_case_id uuid,
    p_evaluation jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.clinical_cases
    set rule_evaluation = p_evaluation,
        updated_at = now()
    where id = p_case_id
      and assigned_clinician_id = auth.uid()
      and status = 'in_progress';

    if not found then
        raise exception 'Clinical case is not available for evaluation';
    end if;
end;
$$;

revoke execute on function public.save_rule_evaluation(uuid, jsonb) 
from public;

grant execute on function public.save_rule_evaluation(uuid, jsonb) 
to authenticated;