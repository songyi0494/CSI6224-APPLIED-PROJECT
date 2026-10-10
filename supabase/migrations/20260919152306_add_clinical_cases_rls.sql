alter table public.clinical_cases
enable row level security;

grant select on table public.clinical_cases
to authenticated;

create policy "Patients can view own clinical cases"
on public.clinical_cases
for select
to authenticated
using (
    patient_id = auth.uid()
);

grant insert on table public.clinical_cases
to authenticated;

create policy "Patients can create own clinical cases"
on public.clinical_cases
for insert
to authenticated
with check (
    patient_id = auth.uid()
    and assigned_clinician_id is null
    and exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'patient'
    )
);

grant update (patient_facts)
on public.clinical_cases
to authenticated;

create policy "Patients can update own draft clinical cases"
on public.clinical_cases
for update
to authenticated
using (
    patient_id = auth.uid()
    and status = 'draft'
    and exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'patient'
    )
)
with check (
    patient_id = auth.uid()
    and status = 'draft'
);