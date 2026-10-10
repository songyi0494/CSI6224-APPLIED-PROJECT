create table public.investigations (
    id uuid primary key default gen_random_uuid(),

    case_id uuid not null unique
        references public.clinical_cases(id) on delete cascade,

    entered_by uuid not null
        references public.profiles(id) on delete restrict,

    vitamin_d_level numeric,
    total_calcium numeric,
    ionised_calcium numeric,
    phosphate numeric,
    tsh numeric,
    body_weight_kg numeric,

    t_score numeric,
    test_date date,

    completed_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    check (vitamin_d_level is null or vitamin_d_level >= 0),
    check (total_calcium is null or total_calcium >= 0),
    check (ionised_calcium is null or ionised_calcium >= 0),
    check (phosphate is null or phosphate >= 0),
    check (body_weight_kg is null or body_weight_kg > 0)
);

-- Automatically update updated_at
create or replace function public.handle_investigation_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger on_investigation_updated
before update on public.investigations
for each row
execute function public.handle_investigation_update();


-- Enable RLS
alter table public.investigations
enable row level security;


-- Remove default access
revoke all
on table public.investigations
from anon, authenticated;


-- Authenticated users receive table-level permissions.
-- RLS policies below still determine which rows they can access.
grant select, insert, update
on table public.investigations
to authenticated;


-- Assigned and approved clinician can view investigations
create policy "Assigned clinician can view investigations"
on public.investigations
for select
to authenticated
using (
    public.is_approved_clinician()
    and exists (
        select 1
        from public.clinical_cases as c
        where c.id = investigations.case_id
          and c.assigned_clinician_id = auth.uid()
    )
);


-- Admin can view investigations
create policy "Admin can view investigations"
on public.investigations
for select
to authenticated
using (public.is_admin());


-- Assigned and approved clinician can create investigations
create policy "Assigned clinician can create investigations"
on public.investigations
for insert
to authenticated
with check (
    public.is_approved_clinician()
    and entered_by = auth.uid()
    and exists (
        select 1
        from public.clinical_cases as c
        where c.id = investigations.case_id
          and c.assigned_clinician_id = auth.uid()
          and c.status = 'in_progress'
    )
);


-- Assigned and approved clinician can update investigations
create policy "Assigned clinician can update investigations"
on public.investigations
for update
to authenticated
using (
    public.is_approved_clinician()
    and entered_by = auth.uid()
    and exists (
        select 1
        from public.clinical_cases as c
        where c.id = investigations.case_id
          and c.assigned_clinician_id = auth.uid()
          and c.status = 'in_progress'
    )
)
with check (
    public.is_approved_clinician()
    and entered_by = auth.uid()
    and exists (
        select 1
        from public.clinical_cases as c
        where c.id = investigations.case_id
          and c.assigned_clinician_id = auth.uid()
          and c.status = 'in_progress'
    )
);
