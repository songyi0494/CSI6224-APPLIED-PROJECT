create table public.clinical_cases (
    id uuid primary key default gen_random_uuid(),

    patient_id uuid not null
        references public.profiles(id)
        on delete cascade,

    assigned_clinician_id uuid
        references public.profiles(id)
        on delete set null,
    
    patient_facts jsonb not null default '{}'::jsonb,
    clinician_facts jsonb not null default '{}'::jsonb,

    pathway text
        check (pathway in ('PATHWAY1', 'PATHWAY2')),
    
    routing_reason text,
    
    status text not null default 'draft'
        check (status in (
            'draft',
            'clinician_input_required',
            'in_progress',
            'evaluated'
        )),
    revision integer not null default 1,

    submitted_at timestamptz, -- patient submitted draft
    claimed_at timestamptz, -- clinician claimed case
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
    
);