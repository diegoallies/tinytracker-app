-- Widen role check constraints to include the 'parent' (Family Member) role.
-- Safe to re-run.

alter table public.baby_shares drop constraint if exists baby_shares_role_check;
alter table public.baby_shares
  add constraint baby_shares_role_check
  check (role in ('owner', 'parent', 'logger', 'viewer'));

-- Same widen for invites so creating a 'parent' invite doesn't fail either.
alter table public.baby_invites drop constraint if exists baby_invites_role_check;
alter table public.baby_invites
  add constraint baby_invites_role_check
  check (role in ('owner', 'parent', 'logger', 'viewer'));
