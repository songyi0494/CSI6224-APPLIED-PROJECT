grant update (clinician_facts)
on public.clinical_cases
to authenticated;

create policy "Clinicians can update assigned clinical cases"
on public.clinical_cases
for update
to authenticated
using (
    assigned_clinician_id = auth.uid()
    and status = 'in_progress'
    and exists (
        select 1
        from public.profiles
        where id = auth.uid()
            and role = 'clinician'
    )
)
with check (
    assigned_clinician_id = auth.uid()
    and status = 'in_progress'
);