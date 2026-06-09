-- ============================================================================
-- TinyTrack production upgrade — 2026-06-09
-- Generated from a live-schema audit (see docs/SUPABASE-AUDIT.md).
--
-- Idempotent: safe to re-run. No destructive statements (no DROP TABLE,
-- no DELETE, no column removals). Apply via the Supabase SQL editor.
-- ============================================================================


-- ============================================================
-- 1. sleeps: columns the Flutter model already reads
-- ============================================================
-- lib/models/sleep_session.dart reads json['quality'] and json['wake_count'],
-- but the live table has neither column, so they are always null in the app.

alter table public.sleeps add column if not exists quality    text;
alter table public.sleeps add column if not exists wake_count integer;


-- ============================================================
-- 2. ai_cache: make cache writes work again
-- ============================================================
-- The app code has since been fixed (commit 38e2e6a) to match the live
-- schema: it now sends user_id, a real DATE in cached_date, and no ai_type.
-- The statements below are belt-and-braces hardening + the read index.

-- a) optional metadata column (no longer required by the app)
alter table public.ai_cache add column if not exists ai_type text;

-- b) populate user_id automatically from the authenticated session
alter table public.ai_cache alter column user_id set default auth.uid();

-- c) widen cached_date to text (existing DATE values cast losslessly;
--    the app's 'YYYY-MM-DD-am/pm' strings then store as-is)
alter table public.ai_cache
  alter column cached_date type text using cached_date::text;

-- Read-path index for: .eq('baby_id', ...).eq('cache_key', ...).maybeSingle()
-- NOTE: intentionally NOT unique — two legacy rows share (baby_id,'insights').
-- New-format cache keys embed the date+period so they never collide.
create index if not exists idx_ai_cache_baby_key
  on public.ai_cache (baby_id, cache_key);

-- CODE FOLLOW-UP (not SQL): the upsert in ai_service.dart has no onConflict
-- target, so it conflicts on the PK only and always inserts a new row.
-- That is harmless once the columns above exist, but if true upsert semantics
-- are wanted, first delete the two legacy 'insights'/'summary-page' rows,
-- add a unique index on (baby_id, cache_key), and pass
-- onConflict: 'baby_id,cache_key' from the app.


-- ============================================================
-- 3. Hot-path indexes for the per-baby log queries
-- ============================================================
-- Every provider filters .eq('baby_id', X) and orders by a timestamp,
-- and the stats/badge/weekly-summary providers also add .gte() range
-- filters on the same timestamp. Composite (baby_id, ts desc) covers both.

create index if not exists idx_feedings_baby_logged
  on public.feedings (baby_id, logged_at desc);

create index if not exists idx_diapers_baby_logged
  on public.diapers (baby_id, logged_at desc);

create index if not exists idx_health_logs_baby_logged
  on public.health_logs (baby_id, logged_at desc);

create index if not exists idx_sleeps_baby_start
  on public.sleeps (baby_id, start_time desc);

create index if not exists idx_tummy_times_baby_start
  on public.tummy_times (baby_id, start_time desc);

create index if not exists idx_growth_baby_measured
  on public.growth (baby_id, measured_at desc);

create index if not exists idx_photos_baby_taken
  on public.photos (baby_id, taken_at desc);

-- milestonesProvider orders by expected_age_months ascending
create index if not exists idx_milestones_baby_expected
  on public.milestones (baby_id, expected_age_months);

-- baby_shares is hit on every RLS check (user_has_baby_access /
-- is_baby_owner filter on user_id + baby_id) and on the shares list screen
create index if not exists idx_baby_shares_user
  on public.baby_shares (user_id, baby_id);
create index if not exists idx_baby_shares_baby
  on public.baby_shares (baby_id);

-- invite acceptance looks rows up by token
create index if not exists idx_baby_invites_token
  on public.baby_invites (token);

create index if not exists idx_baby_medications_baby
  on public.baby_medications (baby_id);


-- ============================================================
-- 4. RLS for the log tables (share-based, matches the app model)
-- ============================================================
-- The repo's migration files only define policies for babies, baby_shares,
-- profiles and baby_medications. The statements below give every member of
-- a baby's share list full CRUD on that baby's logs, using the existing
-- SECURITY DEFINER helper public.user_has_baby_access(uuid)
-- (created in fix_rls_and_sharing.sql — run that file first if this errors).
--
-- Idempotent: drops only its own policy names before recreating.
-- If the dashboard already holds owner-only policies, these are additive
-- (policies are OR'd), which is the intended sharing behavior.

do $$
declare
  t text;
begin
  foreach t in array array[
    'feedings', 'diapers', 'sleeps', 'growth', 'health_logs',
    'milestones', 'tummy_times', 'photos', 'ai_cache'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "members read %s"   on public.%I', t, t);
    execute format('drop policy if exists "members insert %s"  on public.%I', t, t);
    execute format('drop policy if exists "members update %s"  on public.%I', t, t);
    execute format('drop policy if exists "members delete %s"  on public.%I', t, t);

    execute format(
      'create policy "members read %s" on public.%I for select
         using ( public.user_has_baby_access(baby_id) )', t, t);
    execute format(
      'create policy "members insert %s" on public.%I for insert
         with check ( public.user_has_baby_access(baby_id) )', t, t);
    execute format(
      'create policy "members update %s" on public.%I for update
         using ( public.user_has_baby_access(baby_id) )
         with check ( public.user_has_baby_access(baby_id) )', t, t);
    execute format(
      'create policy "members delete %s" on public.%I for delete
         using ( public.user_has_baby_access(baby_id) )', t, t);
  end loop;
end $$;

-- baby_invites: creator manages their invites; acceptance goes through a
-- SECURITY DEFINER RPC so tokens are never readable by other accounts.
-- (A `using (true)` select policy would let any logged-in user harvest
-- tokens and grant themselves access — including owner role.)
alter table public.baby_invites enable row level security;

drop policy if exists "members create invites" on public.baby_invites;
drop policy if exists "authenticated read invites" on public.baby_invites;
drop policy if exists "accept invite" on public.baby_invites;
drop policy if exists "read own invites" on public.baby_invites;

create policy "members create invites"
on public.baby_invites for insert
to authenticated
with check ( public.user_has_baby_access(baby_id) and invited_by = auth.uid() );

create policy "read own invites"
on public.baby_invites for select
to authenticated
using (
  invited_by = auth.uid()
  or used_by = auth.uid()
  or public.user_has_baby_access(baby_id)
);

-- Acceptance: validates the token, creates the share with the role the
-- INVITER chose (never client-supplied), and marks the invite used —
-- atomically, server-side.
create or replace function public.accept_invite(invite_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.baby_invites%rowtype;
  baby_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into inv
    from public.baby_invites
   where token = invite_token
     and used_by is null
     and expires_at > now()
   for update;

  if not found then
    raise exception 'Invite not found, already used, or expired';
  end if;

  if not exists (
    select 1 from public.baby_shares
     where baby_id = inv.baby_id and user_id = auth.uid()
  ) then
    insert into public.baby_shares (baby_id, user_id, role)
    values (inv.baby_id, auth.uid(), inv.role);
  end if;

  update public.baby_invites
     set used_by = auth.uid(), used_at = now()
   where id = inv.id;

  select name into baby_name from public.babies where id = inv.baby_id;
  return jsonb_build_object(
    'baby_id', inv.baby_id, 'baby_name', baby_name, 'role', inv.role);
end $$;

revoke all on function public.accept_invite(text) from public;
grant execute on function public.accept_invite(text) to authenticated;

-- Close the self-insert hole ("or user_id = auth.uid()" from
-- fix_rls_recursion.sql) now that acceptance is server-side.
drop policy if exists "owner inserts shares" on public.baby_shares;
create policy "owner inserts shares"
on public.baby_shares for insert
to authenticated
with check ( public.is_baby_owner(baby_id) );


-- ============================================================
-- 5. Storage policies for the photos and milestones buckets
-- ============================================================
-- fix_rls_and_sharing.sql only covered the avatars bucket. Both buckets are
-- public-read; uploads go to <auth.uid()>/... paths (photo_provider.dart).

drop policy if exists "photos upload own folder"     on storage.objects;
drop policy if exists "photos delete own folder"     on storage.objects;
drop policy if exists "anyone reads photos"          on storage.objects;
drop policy if exists "milestones upload own folder" on storage.objects;
drop policy if exists "milestones delete own folder" on storage.objects;
drop policy if exists "anyone reads milestones"      on storage.objects;

create policy "photos upload own folder"
on storage.objects for insert to authenticated
with check ( bucket_id = 'photos'
             and (storage.foldername(name))[1] = auth.uid()::text );

create policy "photos delete own folder"
on storage.objects for delete to authenticated
using ( bucket_id = 'photos'
        and (storage.foldername(name))[1] = auth.uid()::text );

create policy "anyone reads photos"
on storage.objects for select to public
using ( bucket_id = 'photos' );

create policy "milestones upload own folder"
on storage.objects for insert to authenticated
with check ( bucket_id = 'milestones'
             and (storage.foldername(name))[1] = auth.uid()::text );

create policy "milestones delete own folder"
on storage.objects for delete to authenticated
using ( bucket_id = 'milestones'
        and (storage.foldername(name))[1] = auth.uid()::text );

create policy "anyone reads milestones"
on storage.objects for select to public
using ( bucket_id = 'milestones' );


-- ============================================================
-- 6. Done
-- ============================================================
notify pgrst, 'reload schema';
