-- Adds the per-baby medication catalog used by the feeding/health screens.
-- Owner-only insert/delete enforced both in the app and via RLS.

create table if not exists public.baby_medications (
  id             uuid primary key default gen_random_uuid(),
  baby_id        uuid not null references public.babies(id) on delete cascade,
  name           text not null,
  default_dosage text,
  created_by     uuid not null references auth.users(id),
  created_at     timestamptz not null default now()
);

alter table public.baby_medications enable row level security;

drop policy if exists "members_can_read_meds"   on public.baby_medications;
drop policy if exists "owners_can_insert_meds"  on public.baby_medications;
drop policy if exists "owners_can_delete_meds"  on public.baby_medications;

create policy "members_can_read_meds"
  on public.baby_medications for select
  using (
    exists (
      select 1 from public.baby_shares
      where baby_id = baby_medications.baby_id
        and user_id = auth.uid()
    )
  );

create policy "owners_can_insert_meds"
  on public.baby_medications for insert
  with check (
    exists (
      select 1 from public.baby_shares
      where baby_id = baby_medications.baby_id
        and user_id = auth.uid()
        and role = 'owner'
    )
  );

create policy "owners_can_delete_meds"
  on public.baby_medications for delete
  using (
    exists (
      select 1 from public.baby_shares
      where baby_id = baby_medications.baby_id
        and user_id = auth.uid()
        and role = 'owner'
    )
  );

notify pgrst, 'reload schema';
