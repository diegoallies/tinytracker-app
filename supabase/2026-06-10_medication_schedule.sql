-- ============================================================================
-- Medication schedules & dose-safety — 2026-06-10
-- From the parents' instructions: each medication carries how often it may
-- be given so the app can warn before an accidental double dose.
-- Applied live via the Management API the same night (idempotent).
-- ============================================================================

-- Scheduling columns on the per-baby medication catalog
alter table public.baby_medications add column if not exists frequency_per_day integer
  check (frequency_per_day is null or frequency_per_day between 1 and 12);
alter table public.baby_medications add column if not exists as_needed boolean not null default false;
alter table public.baby_medications add column if not exists min_interval_hours numeric
  check (min_interval_hours is null or min_interval_hours > 0);
alter table public.baby_medications add column if not exists instructions text;

-- One catalog row per medication name per baby
create unique index if not exists idx_baby_medications_unique_name
  on public.baby_medications (baby_id, lower(name));

-- ----------------------------------------------------------------------------
-- Seed Dezhay's regimen (2026-06-10, from the parents):
--   Nexiam once a day · Hyospasmol syrup 3x a day · Retina drops once a day
--   Calpol when needed · Panado when needed (already in catalog)
-- Paracetamol-type (Calpol/Panado): minimum 4 hours between doses, max 4/day.
-- ----------------------------------------------------------------------------
do $$
declare
  b uuid := '6b04bc8e-c85b-45cd-92d0-e2bb29edf4b6'; -- Dezhay Allies
  creator uuid := 'b69f38c3-1d21-4e0f-a509-29663a8a457a'; -- baby owner
begin
  insert into public.baby_medications
      (baby_id, name, default_dosage, created_by, frequency_per_day, as_needed, min_interval_hours, instructions)
  values
      (b, 'Nexiam',           null,  creator, 1,    false, null, 'Once a day'),
      (b, 'Hyospasmol syrup', null,  creator, 3,    false, 4,    '3 times a day'),
      (b, 'Retina drops',     null,  creator, 1,    false, null, 'Once a day'),
      (b, 'Calpol',           null,  creator, null, true,  4,    'Only when needed — max 4 doses in 24h, at least 4h apart')
  on conflict (baby_id, lower(name)) do update
    set frequency_per_day  = excluded.frequency_per_day,
        as_needed          = excluded.as_needed,
        min_interval_hours = excluded.min_interval_hours,
        instructions       = excluded.instructions;

  update public.baby_medications
     set as_needed = true,
         min_interval_hours = 4,
         instructions = 'Only when needed — max 4 doses in 24h, at least 4h apart'
   where baby_id = b and lower(name) = 'panado';
end $$;
