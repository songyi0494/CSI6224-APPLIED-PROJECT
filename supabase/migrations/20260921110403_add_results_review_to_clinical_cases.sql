alter table public.clinical_cases
add column results_review jsonb not null default '{}'::jsonb;