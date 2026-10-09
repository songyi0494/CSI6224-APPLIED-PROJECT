create table public.questionnaire_responses (
    id uuid primary key default gen_random_uuid(),

    patient_id uuid not null unique
        references public.profiles(id) on delete cascade,

    answers jsonb not null default '{}'::jsonb
        check (jsonb_typeof(answers) = 'object'),

    status text not null default 'draft'
        check (status in ('draft', 'submitted')),

    revision integer not null default 1
        check (revision >= 1),

    submitted_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function public.handle_questionnaire_response_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();

    if new.answers is distinct from old.answers then
        new.revision := old.revision + 1;
    else
        new.revision := old.revision;
    end if;

    return new;
end;
$$;

create trigger on_questionnaire_response_updated
before update on public.questionnaire_responses
for each row
execute function public.handle_questionnaire_response_update();

alter table public.questionnaire_responses
enable row level security;

revoke all on table public.questionnaire_responses
from anon, authenticated;

grant select, insert
on table public.questionnaire_responses
to authenticated;

grant update (answers)
on table public.questionnaire_responses
to authenticated;

create policy "Patients can view own questionnaire response"
on public.questionnaire_responses
for select
to authenticated
using (
    patient_id = auth.uid()
    and public.current_user_role() = 'patient'
);

create policy "Patients can create own questionnaire response"
on public.questionnaire_responses
for insert
to authenticated
with check (
    patient_id = auth.uid()
    and status = 'draft'
    and public.current_user_role() = 'patient'
);

create policy "Patients can update own draft response"
on public.questionnaire_responses
for update
to authenticated
using (
    patient_id = auth.uid()
    and status = 'draft'
    and public.current_user_role() = 'patient'
)
with check (
    patient_id = auth.uid()
    and status = 'draft'
    and public.current_user_role() = 'patient'
);