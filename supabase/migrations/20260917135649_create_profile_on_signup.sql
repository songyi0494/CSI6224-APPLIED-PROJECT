create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles(
        id,
        role,
        full_name,
        date_of_birth,
        gender
    )
    values (
        new.id,
        new.raw_user_meta_data ->> 'role',
        new.raw_user_meta_data ->> 'full_name',
        (new.raw_user_meta_data ->> 'date_of_birth')::date,
        new.raw_user_meta_data ->> 'gender'
    );
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();