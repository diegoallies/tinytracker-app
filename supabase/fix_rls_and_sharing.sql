-- TinyTrack: RLS + sharing + baby photo fix.
-- Idempotent: safe to re-run.
-- Run order is preserved top-to-bottom.

-- ============================================================
-- 0. Schema: make sure photo_url exists on babies
-- ============================================================

alter table public.babies add column if not exists photo_url text;

-- ============================================================
-- 1. Helper function (avoids recursive policy loops)
-- ============================================================

create or replace function public.user_has_baby_access(b_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.baby_shares
    where baby_id = b_id and user_id = auth.uid()
  );
$$;

grant execute on function public.user_has_baby_access(uuid) to authenticated;

-- ============================================================
-- 2. baby_shares: anyone sharing a baby can see all co-sharers
-- ============================================================

alter table public.baby_shares enable row level security;

drop policy if exists "select own shares"               on public.baby_shares;
drop policy if exists "view shares for accessible babies" on public.baby_shares;
drop policy if exists "owner manages shares"            on public.baby_shares;

create policy "view shares for accessible babies"
on public.baby_shares for select
using ( public.user_has_baby_access(baby_id) );

create policy "owner manages shares"
on public.baby_shares for all
using (
  exists (
    select 1 from public.baby_shares s
    where s.baby_id = baby_shares.baby_id
      and s.user_id = auth.uid()
      and s.role    = 'owner'
  )
)
with check (
  exists (
    select 1 from public.baby_shares s
    where s.baby_id = baby_shares.baby_id
      and s.user_id = auth.uid()
      and s.role    = 'owner'
  )
  or user_id = auth.uid()  -- accepting your own invite
);

-- ============================================================
-- 3. babies: read for any sharer, write/delete for owner only
-- ============================================================

alter table public.babies enable row level security;

drop policy if exists "select own babies"   on public.babies;
drop policy if exists "view babies you share" on public.babies;
drop policy if exists "user creates baby"   on public.babies;
drop policy if exists "owner updates baby"  on public.babies;
drop policy if exists "owner deletes baby"  on public.babies;

create policy "view babies you share"
on public.babies for select
using ( public.user_has_baby_access(id) );

create policy "user creates baby"
on public.babies for insert
with check ( auth.uid() = user_id );

create policy "owner updates baby"
on public.babies for update
using (
  exists (
    select 1 from public.baby_shares
    where baby_id = babies.id
      and user_id = auth.uid()
      and role    = 'owner'
  )
)
with check ( true );

create policy "owner deletes baby"
on public.babies for delete
using ( owner_id = auth.uid() );

-- ============================================================
-- 4. profiles: visible to anyone you share a baby with
-- ============================================================

alter table public.profiles enable row level security;

drop policy if exists "view own profile"      on public.profiles;
drop policy if exists "view co-share profiles" on public.profiles;
drop policy if exists "update own profile"    on public.profiles;

create policy "view co-share profiles"
on public.profiles for select
using (
  id = auth.uid()
  or exists (
    select 1 from public.baby_shares s1
    join public.baby_shares s2 on s1.baby_id = s2.baby_id
    where s1.user_id = auth.uid()
      and s2.user_id = profiles.id
  )
);

create policy "update own profile"
on public.profiles for update
using ( id = auth.uid() )
with check ( id = auth.uid() );

-- ============================================================
-- 5. Storage: avatars bucket (used for both profile and baby photos)
-- ============================================================
-- IMPORTANT: also toggle the avatars bucket to PUBLIC in the
-- Supabase dashboard (Storage → avatars → Configuration → Public).

drop policy if exists "users upload to own folder" on storage.objects;
drop policy if exists "users update own files"    on storage.objects;
drop policy if exists "anyone reads avatars"      on storage.objects;

create policy "users upload to own folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "users update own files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "anyone reads avatars"
on storage.objects for select
to public
using ( bucket_id = 'avatars' );
