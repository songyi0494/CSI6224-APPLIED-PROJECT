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
    'Have you experienced a fracture caused by a fall from standing height or less?',
    'single_choice',
    '["Yes", "No"]'::jsonb,
    true,
    6,
    'minimalTraumaFracture',
    null
),
(
    'Was the fracture in your hand, foot, face, or ankle?',
    'single_choice',
    '["Yes", "No"]'::jsonb,
    false,
    7,
    'excludedFractureSite',
    null
)
on conflict (field_key) do nothing;