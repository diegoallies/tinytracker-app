-- Push device tokens for FCM (Firebase Cloud Messaging).
-- Each user can have multiple devices; we store the FCM registration token per
-- device. FCM reaches iOS through APNs itself, so both platforms share this
-- table and `platform` is informational only.
create table if not exists public.device_tokens (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  token      text        not null,
  platform   text        not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.device_tokens enable row level security;

-- A user may only read / write their own tokens. The notify function runs with
-- the service role, which bypasses RLS to read the recipients' tokens.
drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own" on public.device_tokens
  for select using (auth.uid() = user_id);

drop policy if exists "device_tokens_insert_own" on public.device_tokens;
create policy "device_tokens_insert_own" on public.device_tokens
  for insert with check (auth.uid() = user_id);

drop policy if exists "device_tokens_update_own" on public.device_tokens;
create policy "device_tokens_update_own" on public.device_tokens
  for update using (auth.uid() = user_id);

drop policy if exists "device_tokens_delete_own" on public.device_tokens;
create policy "device_tokens_delete_own" on public.device_tokens
  for delete using (auth.uid() = user_id);

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
