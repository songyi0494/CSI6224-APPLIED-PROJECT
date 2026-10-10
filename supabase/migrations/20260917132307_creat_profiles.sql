create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    role text not null 
        check (role in ('patient', 'clinician')),
    full_name text,
    date_of_birth date,
    gender text,
    created_at timestamptz not null default now()
);