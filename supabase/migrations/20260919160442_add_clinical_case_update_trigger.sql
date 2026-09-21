create or replace function public.handle_clinical_case_patient_update()
returns trigger
language plpgsql
as $$
begin
    if new.patient_facts is distinct from old.patient_facts then
        new.revision := old.revision + 1;
        new.updated_at := now();
    end if;

    return new;
end;
$$;

create trigger on_clinical_case_patient_update
before update of patient_facts
on public.clinical_cases
for each row
execute function public.handle_clinical_case_patient_update();