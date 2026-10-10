create policy "Clinician can view available or assigned clinical cases"
on public.clinical_cases
for select
to authenticated
using (
    exists (
        select 1
        from public.profiles
        where id = auth.uid()
            and role = 'clinician'
    )
    and (
        (
            status = 'clinician_input_required'
            and assigned_clinician_id is null
        )
        or 
        assigned_clinician_id = auth.uid()
    )
)