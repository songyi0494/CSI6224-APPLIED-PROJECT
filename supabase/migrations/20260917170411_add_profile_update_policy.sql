grant update (
    full_name,
    date_of_birth,
    gender
)
on table public.profiles
to authenticated;

create policy "User can update own profile"
on public.profiles
for update
to authenticated
using (
    id = auth.uid()
)
with check (
    id = auth.uid()
);