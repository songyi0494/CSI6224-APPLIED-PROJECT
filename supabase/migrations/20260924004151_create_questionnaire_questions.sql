create table public.questionnaire_questions (
    id uuid primary key default gen_random_uuid(),
    question_text text not null,
    question_type text not null 
        check (
            question_type in (
                'text',
                'numeric',
                'checkbox',
                'single_choice',
                'multi_choice',
                'dropdown',
                'scale'
            )
        ),
    options jsonb,
    is_required boolean not null default false,
    display_order integer not null,
    field_key text unique,
    created_by uuid
        references public.profiles(id) on delete restrict,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function public.handle_questionnaire_question_update()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger on_questionnaire_question_update
before update
on public.questionnaire_questions
for each row 
execute function public.handle_questionnaire_question_update();

create or replace function public.protect_system_question_update()
returns trigger
language plpgsql
as $$
begin
    if new.field_key is distinct from old.field_key then
        raise exception 'Question field_key cannot be changed';
    end if;

    if old.field_key is not null
       and new.question_type is distinct from old.question_type then
        raise exception 'System question type cannot be changed';
    end if;

    return new;
end;
$$;

create trigger on_system_question_update
before update
on public.questionnaire_questions
for each row
execute function public.protect_system_question_update();

create or replace function public.protect_system_question_delete()
returns trigger
language plpgsql
as $$
begin
    if old.field_key is not null then
        raise exception 'System question cannot be deleted';
    end if;

    return old;
end;
$$;

create trigger on_system_question_delete
before delete
on public.questionnaire_questions
for each row
execute function public.protect_system_question_delete();

alter table public.questionnaire_questions
enable row level security;

grant select
on table public.questionnaire_questions
to authenticated;

create policy "Authenticated users can view questionnaire questions"
on public.questionnaire_questions
for select
to authenticated
using (true);

grant insert, update, delete
on table public.questionnaire_questions
to authenticated;

create policy "Clinicians can create questionnaire questions"
on public.questionnaire_questions
for insert
to authenticated
with check (
    created_by = auth.uid()
    and field_key is null
    and exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'clinician'
    )
);

create policy "Clinicians can update questionnaire questions"
on public.questionnaire_questions
for update
to authenticated
using (
    exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'clinician'
    )
)
with check (
    exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'clinician'
    )
);

create policy "Clinicians can delete questionnaire questions"
on public.questionnaire_questions
for delete
to authenticated
using (
    exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and role = 'clinician'
    )
);

-- Initialize system data
insert into public.questionnaire_questions (
    question_text,
    question_type,
    options,
    is_required,
    display_order,
    field_key,
    created_by
)
values
(
    'What is your sex?',
    'single_choice',
    '["Female", "Male"]'::jsonb,
    true,
    1,
    'sex',
    null
),
(
    'Are you postmenopausal?',
    'single_choice',
    '["Yes", "No"]'::jsonb,
    true,
    2,
    'postmenopausal',
    null
),
(
    'How many servings of dairy do you have per day?',
    'numeric',
    null,
    true,
    3,
    'dietaryDairyServings',
    null
),
(
    'Do you currently smoke?',
    'single_choice',
    '["Yes", "No"]'::jsonb,
    true,
    4,
    'smoking',
    null
),
(
    'Do you currently drink alcohol?',
    'single_choice',
    '["Yes", "No"]'::jsonb,
    true,
    5,
    'alcohol',
    null
);