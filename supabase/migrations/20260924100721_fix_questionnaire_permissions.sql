drop policy if exists "Clinicians can create questionnaire questions"
on public.questionnaire_questions;

drop policy if exists "Clinicians can update questionnaire questions"
on public.questionnaire_questions;

drop policy if exists "Clinicians can delete questionnaire questions"
on public.questionnaire_questions;


create policy "Approved clinicians and admins can create questions"
on public.questionnaire_questions
for insert
to authenticated
with check (
    (
        public.is_approved_clinician()
        or public.is_admin()
    )
    and created_by = auth.uid()
    and field_key is null
);


create policy "Approved clinicians and admins can update questions"
on public.questionnaire_questions
for update
to authenticated
using (
    public.is_approved_clinician()
    or public.is_admin()
)
with check (
    public.is_approved_clinician()
    or public.is_admin()
);


create policy "Approved clinicians and admins can delete questions"
on public.questionnaire_questions
for delete
to authenticated
using (
    public.is_approved_clinician()
    or public.is_admin()
);