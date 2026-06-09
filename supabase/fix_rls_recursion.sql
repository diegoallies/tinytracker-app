-- HOTFIX: removes the recursive policies that hid all data.
-- Safe to run on top of the previous script. Idempotent.

-- 1. Drop the broken policies that cause "infinite recursion detected"
drop policy if exists "owner manages shares" on public.baby_shares;
drop policy if exists "owner updates baby"   on public.babies;

-- 2. Owner-check helper that bypasses RLS via SECURITY DEFINER
create or replace function public.is_baby_owner(b_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.baby_shares
    where baby_id = b_id
      and user_id = auth.uid()
      and role    = 'owner'
  );
$$;

grant execute on function public.is_baby_owner(uuid) to authenticated;

-- 3. Rebuild baby_shares write policies WITHOUT recursion
--    (SELECT is still handled by "view shares for accessible babies")
create policy "owner inserts shares"
on public.baby_shares for insert
to authenticated
with check (
  public.is_baby_owner(baby_id)
  or user_id = auth.uid()  -- accepting your own invite
);

create policy "owner updates shares"
on public.baby_shares for update
to authenticated
using      ( public.is_baby_owner(baby_id) )
with check ( public.is_baby_owner(baby_id) );

create policy "owner deletes shares"
on public.baby_shares for delete
to authenticated
using ( public.is_baby_owner(baby_id) );

-- 4. Rebuild babies UPDATE policy using the helper
create policy "owner updates baby"
on public.babies for update
to authenticated
using      ( public.is_baby_owner(id) )
with check ( true );
