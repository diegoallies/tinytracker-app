-- ============================================================================
-- TinyTrack immunisations (SA EPI schedule tracker) - 2026-06-10
-- Applied directly via the Management API the same night (idempotent).
-- ============================================================================

create table if not exists public.immunisations (
  id          uuid primary key default gen_random_uuid(),
  baby_id     uuid not null references public.babies(id) on delete cascade,
  user_id     uuid not null default auth.uid(),
  vaccine_key text not null,  -- key into the app's static SA EPI schedule data
  given_on    date,
  notes       text,
  created_at  timestamptz not null default now(),
  unique (baby_id, vaccine_key)
);

create index if not exists idx_immunisations_baby
  on public.immunisations (baby_id);

alter table public.immunisations enable row level security;

drop policy if exists "immunisations_select_members" on public.immunisations;
create policy "immunisations_select_members" on public.immunisations
  for select using ( public.user_has_baby_access(baby_id) );

drop policy if exists "immunisations_insert_members" on public.immunisations;
create policy "immunisations_insert_members" on public.immunisations
  for insert with check ( public.user_has_baby_access(baby_id) );

drop policy if exists "immunisations_update_members" on public.immunisations;
create policy "immunisations_update_members" on public.immunisations
  for update using ( public.user_has_baby_access(baby_id) )
  with check ( public.user_has_baby_access(baby_id) );

drop policy if exists "immunisations_delete_members" on public.immunisations;
create policy "immunisations_delete_members" on public.immunisations
  for delete using ( public.user_has_baby_access(baby_id) );

-- given_on is required (applied live 2026-06-10): the app always writes it,
-- and a null row would have crashed the list parse.
update public.immunisations set given_on = created_at::date where given_on is null;
alter table public.immunisations alter column given_on set default (now()::date);
alter table public.immunisations alter column given_on set not null;
