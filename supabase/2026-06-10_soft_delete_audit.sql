-- ============================================================================
-- Soft delete + audit trail — 2026-06-10
-- Diego: "Nothing truly gets deleted, only marked as deleted" + full
-- created/modified audit columns. Applied live via the Management API.
--
-- Per data table:
--   created_at (existed) + user_id (creator, existed) stay as-is
--   updated_at / updated_by  — maintained automatically by trigger
--   deleted_at / deleted_by  — set by the app instead of DELETE
-- Access-control tables (baby_shares, baby_invites) keep HARD deletes:
-- a soft-deleted share would still grant access through RLS.
-- ============================================================================

create or replace function public.touch_audit()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  -- Stamp who soft-deleted when deleted_at is being set
  if new.deleted_at is not null and old.deleted_at is null then
    new.deleted_by = auth.uid();
  end if;
  return new;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'feedings','diapers','sleeps','growth','health_logs','milestones',
    'tummy_times','photos','babies','baby_medications','reflux_events',
    'daily_journals','weekly_reports','monthly_reviews','emergency_contacts',
    'immunisations'
  ] loop
    execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', t);
    execute format('alter table public.%I add column if not exists updated_by uuid', t);
    execute format('alter table public.%I add column if not exists deleted_at timestamptz', t);
    execute format('alter table public.%I add column if not exists deleted_by uuid', t);

    -- One audit trigger per table (replaces the older touch_updated_at ones)
    execute format('drop trigger if exists trg_%s_touch on public.%I', t, t);
    execute format('drop trigger if exists trg_%s_audit on public.%I', t, t);
    execute format(
      'create trigger trg_%s_audit before update on public.%I
         for each row execute function public.touch_audit()', t, t);
  end loop;
end $$;
