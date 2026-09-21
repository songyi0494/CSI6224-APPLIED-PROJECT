alter table public.patient_assignments
enable row level security;

grant select on table public.patient_assignments
to authenticated;

create policy "Clinicians can view own assignments"
on public.patient_assignments
for select
to authenticated
using (
    clinician_id = auth.uid()
);