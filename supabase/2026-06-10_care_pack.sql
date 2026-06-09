-- ============================================================================
-- TinyTrack "Care Pack" schema — 2026-06-10
-- Digitises the Allies Family Baby Care Tracking & Reporting Pack (paper).
--
-- Idempotent: safe to re-run. No destructive statements.
-- Apply AFTER (or together with) 2026-06-09_production_upgrade.sql, which
-- defines the public.user_has_baby_access(uuid) RLS helper this file reuses.
-- ============================================================================


-- ============================================================
-- 1. Per-feed detail: quality + spit-up (Daily Log "Feeds" table)
-- ============================================================
alter table public.feedings add column if not exists quality integer
  check (quality is null or quality between 1 and 5);
alter table public.feedings add column if not exists had_spitup boolean
  not null default false;

-- ============================================================
-- 2. Per-nappy stool type, Bristol-style 1-7 (Tummy & Digestion)
-- ============================================================
alter table public.diapers add column if not exists stool_type integer
  check (stool_type is null or stool_type between 1 and 7);

-- ============================================================
-- 3. Reflux events (Reflux Tracker — daily, severity 1-5)
-- ============================================================
create table if not exists public.reflux_events (
  id             uuid primary key default gen_random_uuid(),
  baby_id        uuid not null references public.babies(id) on delete cascade,
  user_id        uuid not null default auth.uid(),
  severity       integer not null check (severity between 1 and 5),
  painful_crying boolean not null default false,
  arching_back   boolean not null default false,
  trigger        text,
  notes          text,
  logged_at      timestamptz not null default now(),
  created_at     timestamptz not null default now()
);
create index if not exists idx_reflux_events_baby_time
  on public.reflux_events (baby_id, logged_at desc);

-- ============================================================
-- 4. Daily journal (Mood & Activity + cramps/gas, one row per day)
-- ============================================================
create table if not exists public.daily_journals (
  id           uuid primary key default gen_random_uuid(),
  baby_id      uuid not null references public.babies(id) on delete cascade,
  user_id      uuid not null default auth.uid(),
  journal_date date not null,
  mood         text check (mood is null or mood in ('happy','okay','fussy','very_fussy')),
  cramps       integer check (cramps is null or cramps between 0 and 3),
  gas          integer check (gas is null or gas between 0 and 3),
  fussy_times  text,
  activities   text,
  new_things   text,
  upsets       text,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (baby_id, journal_date)
);
create index if not exists idx_daily_journals_baby_date
  on public.daily_journals (baby_id, journal_date desc);

-- ============================================================
-- 5. Weekly reports by age (nanny -> parents, every Friday)
-- ============================================================
-- milestone_checks: { "<item key>": "first_time" | "better" | "not_yet" }
-- focus_answers:    { "<question key>": "<free text>" }
-- metrics:          auto-computed snapshot (feeds/day, ml avg, naps, wakings,
--                   spit-ups/day, tummy-time total, ...) frozen at submit time
create table if not exists public.weekly_reports (
  id               uuid primary key default gen_random_uuid(),
  baby_id          uuid not null references public.babies(id) on delete cascade,
  user_id          uuid not null default auth.uid(),
  week_start       date not null,
  age_stage        text not null,
  summary          text,
  struggles        text,
  questions        text,
  milestone_checks jsonb not null default '{}'::jsonb,
  focus_answers    jsonb not null default '{}'::jsonb,
  metrics          jsonb not null default '{}'::jsonb,
  submitted_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (baby_id, week_start)
);
create index if not exists idx_weekly_reports_baby_week
  on public.weekly_reports (baby_id, week_start desc);

-- ============================================================
-- 6. Monthly milestone reviews (on the 4th, longer-form checklist)
-- ============================================================
-- checklist: { "<item key>": "yes" | "sometimes" | "not_yet" }
create table if not exists public.monthly_reviews (
  id           uuid primary key default gen_random_uuid(),
  baby_id      uuid not null references public.babies(id) on delete cascade,
  user_id      uuid not null default auth.uid(),
  review_month date not null,
  age_stage    text not null,
  checklist    jsonb not null default '{}'::jsonb,
  comments     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (baby_id, review_month)
);
create index if not exists idx_monthly_reviews_baby_month
  on public.monthly_reviews (baby_id, review_month desc);

-- ============================================================
-- 7. Emergency contact sheet (kept "on the fridge", now in-app)
-- ============================================================
create table if not exists public.emergency_contacts (
  id         uuid primary key default gen_random_uuid(),
  baby_id    uuid not null references public.babies(id) on delete cascade,
  user_id    uuid not null default auth.uid(),
  label      text not null,
  name       text,
  phone      text,
  notes      text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_emergency_contacts_baby
  on public.emergency_contacts (baby_id, sort_order);

-- ============================================================
-- 8. RLS — same share-based policy shape as the other log tables
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'reflux_events', 'daily_journals', 'weekly_reports',
    'monthly_reviews', 'emergency_contacts'
  ] loop
    execute format('alter table public.%I enable row level security', t);

    execute format(
      'drop policy if exists "%s_select_members" on public.%I', t, t);
    execute format(
      'create policy "%s_select_members" on public.%I for select
         using ( public.user_has_baby_access(baby_id) )', t, t);

    execute format(
      'drop policy if exists "%s_insert_members" on public.%I', t, t);
    execute format(
      'create policy "%s_insert_members" on public.%I for insert
         with check ( public.user_has_baby_access(baby_id) )', t, t);

    execute format(
      'drop policy if exists "%s_update_members" on public.%I', t, t);
    execute format(
      'create policy "%s_update_members" on public.%I for update
         using ( public.user_has_baby_access(baby_id) )
         with check ( public.user_has_baby_access(baby_id) )', t, t);

    execute format(
      'drop policy if exists "%s_delete_members" on public.%I', t, t);
    execute format(
      'create policy "%s_delete_members" on public.%I for delete
         using ( public.user_has_baby_access(baby_id) )', t, t);
  end loop;
end $$;

-- updated_at maintenance
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'daily_journals', 'weekly_reports', 'monthly_reviews', 'emergency_contacts'
  ] loop
    execute format('drop trigger if exists trg_%s_touch on public.%I', t, t);
    execute format(
      'create trigger trg_%s_touch before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;
