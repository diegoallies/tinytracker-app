create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Record tables without ON DELETE CASCADE: remove rows the user logged
  -- anywhere, plus all rows on babies the user owns.
  delete from diapers     where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from feedings    where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from growth      where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from health_logs where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from milestones  where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from photos      where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from sleeps      where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);
  delete from tummy_times where user_id = uid or baby_id in (select id from babies where owner_id = uid or user_id = uid);

  -- Owned babies; the remaining child tables cascade from here.
  delete from babies where owner_id = uid or user_id = uid;

  -- Membership on other people's babies and invites this user issued.
  delete from baby_shares where user_id = uid;
  delete from baby_invites where invited_by = uid;

  -- Remaining user-scoped tables.
  delete from ai_cache where user_id = uid;
  delete from daily_journals where user_id = uid;
  delete from emergency_contacts where user_id = uid;


  delete from profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
