-- Schedule the overdue feed/sleep check every 15 minutes.
--
-- Run this AFTER:
--   1. supabase/2026-07-25_push_reminders.sql   (tables)
--   2. supabase functions deploy check-overdue --no-verify-jwt
--
-- Safe to re-run: every statement below is idempotent.
--
-- The function is deployed with --no-verify-jwt because pg_cron has no user JWT
-- to present, which would otherwise leave the URL callable by anyone. It is
-- protected instead by the CRON_SECRET header checked inside the function.
--
-- The secret is inlined below rather than left as a placeholder, so this file
-- runs as-is. That is a deliberate call on the basis that this repo is private.
-- If it ever goes public, rotate it: `openssl rand -hex 32`, then update BOTH
-- `supabase secrets set CRON_SECRET=...` and the value here.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Same value as the CRON_SECRET edge-function secret. vault.create_secret
-- errors if the name already exists, so update in place when it does — that
-- keeps this file re-runnable.
do $do$
declare
  v_secret text := 'ce7129cf88c922b5f80b3794c8b29f0367f6a8d0fbd5716254aa1629bf11617e';
  v_id     uuid;
begin
  select id into v_id from vault.secrets where name = 'cron_secret';
  if v_id is null then
    perform vault.create_secret(
      v_secret,
      'cron_secret',
      'Shared secret for authenticating pg_cron calls to edge functions'
    );
  else
    perform vault.update_secret(v_id, v_secret);
  end if;
end
$do$;

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
-- Recent runs (look for status = 'succeeded'). Note job_run_details keys on
-- jobid, not jobname, so it needs the join:
--   select j.jobname, d.status, d.return_message, d.start_time
--   from cron.job_run_details d
--   join cron.job j on j.jobid = d.jobid
--   order by d.start_time desc limit 10;
--
-- What the function actually returned (pg_net logs responses separately):
--   select id, status_code, content from net._http_response
--   order by created desc limit 10;
--
-- Or just call it by hand:
--   curl -X POST https://ggbjcjmksxxkbjaxxogv.supabase.co/functions/v1/check-overdue \
--     -H 'x-cron-secret: <your secret>'
