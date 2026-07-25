-- Server-driven feed / sleep reminders.
--
-- Replaces the on-device flutter_local_notifications scheduling for feeds and
-- sleeps. Local scheduling could only reflect what THAT phone knew: if the nanny
-- logged a feed and the parent's app hadn't refreshed, the parent's reminder was
-- based on stale data. A cron job reading the database is the single source of
-- truth for every caregiver at once.
--
-- Two tables:
--   notification_prefs  — the settings previously kept in SharedPreferences,
--                         moved server-side because a cron job can't read a
--                         phone's local storage.
--   push_alerts_sent    — dedup ledger. The cron runs every 15 minutes; without
--                         this it would re-send "baby hasn't eaten" every run.

-- ── Preferences ──────────────────────────────────────────────────────────────
create table if not exists public.notification_prefs (
  user_id                  uuid        primary key references auth.users(id) on delete cascade,
  feeding_enabled          boolean     not null default false,
  -- Fallback interval, used when the last feed recorded no volume. When a volume
  -- IS recorded the server scales the interval by age-based guidelines instead,
  -- mirroring FeedingGuidelines in the app.
  feeding_interval_minutes integer     not null default 180,
  sleep_enabled            boolean     not null default false,
  sleep_window_minutes     integer     not null default 120,
  medication_enabled       boolean     not null default false,
  weekly_report_enabled    boolean     not null default false,
  updated_at               timestamptz not null default now(),
  constraint feeding_interval_sane check (feeding_interval_minutes between 30 and 720),
  constraint sleep_window_sane     check (sleep_window_minutes     between 30 and 720)
);

alter table public.notification_prefs enable row level security;

drop policy if exists "notification_prefs_select_own" on public.notification_prefs;
create policy "notification_prefs_select_own" on public.notification_prefs
  for select using (auth.uid() = user_id);

drop policy if exists "notification_prefs_insert_own" on public.notification_prefs;
create policy "notification_prefs_insert_own" on public.notification_prefs
  for insert with check (auth.uid() = user_id);

drop policy if exists "notification_prefs_update_own" on public.notification_prefs;
create policy "notification_prefs_update_own" on public.notification_prefs
  for update using (auth.uid() = user_id);

drop policy if exists "notification_prefs_delete_own" on public.notification_prefs;
create policy "notification_prefs_delete_own" on public.notification_prefs
  for delete using (auth.uid() = user_id);

-- ── Dedup ledger ─────────────────────────────────────────────────────────────
-- `anchor_at` is the event the alert is ABOUT: the last feed's logged_at, or the
-- last wake's end_time. Keying on it means one "due" and one "overdue" alert per
-- real event — and logging a new feed naturally moves the anchor, which re-arms
-- the alerts without any explicit reset.
create table if not exists public.push_alerts_sent (
  baby_id    uuid        not null references public.babies(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  alert_type text        not null,
  anchor_at  timestamptz not null,
  sent_at    timestamptz not null default now(),
  primary key (baby_id, user_id, alert_type, anchor_at)
);

alter table public.push_alerts_sent enable row level security;

-- Only the service role (the edge function) touches this. Users may read their
-- own rows for debugging; nothing in the app writes here.
drop policy if exists "push_alerts_sent_select_own" on public.push_alerts_sent;
create policy "push_alerts_sent_select_own" on public.push_alerts_sent
  for select using (auth.uid() = user_id);

create index if not exists push_alerts_sent_sent_at_idx
  on public.push_alerts_sent(sent_at);

-- Housekeeping: the ledger only needs enough history to stop duplicates. Call
-- from the cron job (or a separate schedule) to keep it small.
create or replace function public.prune_push_alerts_sent()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_alerts_sent where sent_at < now() - interval '7 days';
$$;
