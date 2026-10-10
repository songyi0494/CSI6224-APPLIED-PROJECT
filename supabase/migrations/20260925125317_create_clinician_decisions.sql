create table public.clinician_decisions (
    id uuid primary key default gen_random_uuid(),
    
    case_id uuid not null unique
        references public.clinical_cases(id) on delete cascade,
    
    clinician_id uuid not null
        references public.profiles(id) on delete restrict,
    
    decision text not null
        check (decision in ('approved', 'rejected')),
    
    notes text,
    
    pathway_revision integer not null
        check (pathway_revision >= 0),
    
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);