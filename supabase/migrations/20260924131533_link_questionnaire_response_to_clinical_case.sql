alter table public.clinical_cases
add column questionnaire_response_id uuid
    references public.questionnaire_responses(id) on delete restrict;

alter table public.clinical_cases
add constraint clinical_cases_questionnaire_response_unique
unique (questionnaire_response_id);

create policy "Clinicians can view available or assigned responses"
on public.questionnaire_responses
for select
to authenticated
using (
    public.is_approved_clinician()
    and status = 'submitted'
    and exists (
        select 1
        from public.clinical_cases as c
        where c.questionnaire_response_id = questionnaire_responses.id
          and (
              (
                  c.assigned_clinician_id is null
                  and c.status = 'clinician_input_required'
              )
              or c.assigned_clinician_id = auth.uid()
          )
    )
);


create policy "Admins can view questionnaire responses"
on public.questionnaire_responses
for select
to authenticated
using (public.is_admin());