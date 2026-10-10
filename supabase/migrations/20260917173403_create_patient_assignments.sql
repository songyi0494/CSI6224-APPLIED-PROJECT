create table public.patient_assignments (
    clinician_id uuid not null
        references public.profiles(id)
        on delete cascade,

    patient_id uuid not null
        references public.profiles(id)
        on delete cascade,

    created_at timestamptz not null default now(),

    primary key (clinician_id, patient_id)
);