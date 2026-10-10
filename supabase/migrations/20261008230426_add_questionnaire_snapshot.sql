alter table public.questionnaire_responses
add column if not exists questions_snapshot jsonb;