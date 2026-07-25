-- Schedule the overdue feed/sleep check every 15 minutes.
--
-- Run this AFTER:
--   1. supabase/2026-07-25_push_reminders.sql   (tables)
--   2. supabase functions deploy check-overdue --no-verify-jwt
--   3. supabase secrets set CRON_SECRET=<a long random string>
--
-- Generate the secret with:  openssl rand -hex 32
--
-- The function is deployed with --no-verify-jwt because pg_cron has no user JWT
-- to present. It's protected instead by the CRON_SECRET header checked inside
-- the function, so the endpoint isn't an open push-spam vector. Storing that
-- secret in Vault keeps it out of this file and out of git.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Store the same value you passed to `supabase secrets set CRON_SECRET`.
-- Replace <PASTE_THE_SAME_CRON_SECRET_HERE> before running.
select vault.create_secret(
  '<PASTE_THE_SAME_CRON_SECRET_HERE>',
  'cron_secret',
  'Shared secret for authenticating pg_cron calls to edge functions'
);

-- Idempotent: drop any previous schedule with this name before creating it.
select cron.unschedule('check-overdue-every-15-min')
where exists (
  select 1 from cron.job where jobname = 'check-overdue-every-15-min'
);

select cron.schedule(
  'check-overdue-every-15-min',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://ggbjcjmksxxkbjaxxogv.supabase.co/functions/v1/check-overdue',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-cron-secret',  (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- Keep the dedup ledger from growing forever. Daily at 03:20.
select cron.unschedule('prune-push-alerts')
where exists (select 1 from cron.job where jobname = 'prune-push-alerts');

select cron.schedule(
  'prune-push-alerts',
  '20 3 * * *',
  $$ select public.prune_push_alerts_sent(); $$
);

-- ── Verifying it works ───────────────────────────────────────────────────────
-- Scheduled jobs:
--   select jobid, jobname, schedule, active from cron.job;
--
-- Recent runs (look for status = 'succeeded'):
--   select jobname, status, return_message, start_time
--   from cron.job_run_details order by start_time desc limit 10;
--
-- What the function actually returned (pg_net logs responses separately):
--   select id, status_code, content from net._http_response
--   order by created desc limit 10;
--
-- Or just call it by hand:
--   curl -X POST https://ggbjcjmksxxkbjaxxogv.supabase.co/functions/v1/check-overdue \
--     -H 'x-cron-secret: <your secret>'
