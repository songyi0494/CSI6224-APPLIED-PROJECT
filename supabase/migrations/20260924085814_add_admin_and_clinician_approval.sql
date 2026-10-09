-- Add administrator role
alter table public.profiles
drop constraint profiles_role_check;

alter table public.profiles
add constraint profiles_role_check
check (role in ('patient', 'clinician', 'admin'));

-- Add clinician approval fields
alter table public.profiles
add column approval_status text not null default 'approved'
check (approval_status in ('pending', 'approved', 'rejected'));

alter table public.profiles
add column approval_reviewed_by uuid
references public.profiles(id) on delete set null;

alter table public.profiles
add column approval_reviewed_at timestamptz;

alter table public.profiles
add column updated_at timestamptz not null default now();

-- Update automatic profile creation
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    requested_role text;
begin
    requested_role := new.raw_user_meta_data ->> 'role';

    -- Users cannot create an admin account through normal signup
    if requested_role not in ('patient', 'clinician') then
        raise exception 'Invalid registration role';
    end if;

    insert into public.profiles (
        id,
        role,
        full_name,
        date_of_birth,
        gender,
        approval_status
    )
    values (
        new.id,
        requested_role,
        new.raw_user_meta_data ->> 'full_name',
        nullif(new.raw_user_meta_data ->> 'date_of_birth','')::date,
        new.raw_user_meta_data ->> 'gender',
        case
            when requested_role = 'clinician' then 'pending'
            else 'approved'
        end
    );
    return new;
end;
$$;

-- Return the current user's role
create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select p.role
    from public.profiles as p
    where p.id = auth.uid();
$$;


-- Check whether the current user is an approved clinician
create or replace function public.is_approved_clinician()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles as p
        where p.id = auth.uid()
          and p.role = 'clinician'
          and p.approval_status = 'approved'
    );
$$;


-- Check whether the current user is an administrator
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.profiles as p
        where p.id = auth.uid()
          and p.role = 'admin'
          and p.approval_status = 'approved'
    );
$$;

-- Administrator approves or rejects a clinician
create or replace function public.review_clinician(
    p_clinician_id uuid,
    p_approval text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- Login check
    if auth.uid() is null then
        raise exception 'Authentication required'
            using errcode = '42501';
    end if;

    -- Admin check
    if not public.is_admin() then
        raise exception 'Administrator access required'
            using errcode = '42501';
    end if;

    -- Only approved or rejected is accepted
    if p_approval not in ('approved', 'rejected') then
        raise exception 'Invalid clinician approval status'
            using errcode = '22023';
    end if;

    update public.profiles
    set
        approval_status = p_approval,
        approval_reviewed_by = auth.uid(),
        approval_reviewed_at = now(),
        updated_at = now()
    where id = p_clinician_id
      and role = 'clinician';

    if not found then
        raise exception 'Clinician account not found'
            using errcode = 'P0002';
    end if;
end;
$$;

-- Administrator can view every profile, including pending clinicians
create policy "Admins can view all profiles"
on public.profiles
for select
to authenticated
using (public.is_admin());

revoke all on function public.current_user_role()
from public, anon;
revoke all on function public.is_approved_clinician()
from public, anon;
revoke all on function public.is_admin()
from public, anon;
revoke all on function public.review_clinician(uuid, text)
from public, anon;

grant execute on function public.current_user_role()
to authenticated;
grant execute on function public.is_approved_clinician()
to authenticated;
grant execute on function public.is_admin()
to authenticated;

grant execute on function public.review_clinician(uuid, text)
to authenticated;