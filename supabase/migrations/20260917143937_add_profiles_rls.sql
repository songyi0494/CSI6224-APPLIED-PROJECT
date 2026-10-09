alter table public.profiles
enable row level security;

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using (
    id = auth.uid()
);