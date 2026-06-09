# Supabase Production Audit — TinyTrack

- **Date:** 2026-06-09
- **Project:** `ggbjcjmksxxkbjaxxogv` (https://ggbjcjmksxxkbjaxxogv.supabase.co)
- **Method:** PostgREST OpenAPI introspection + `Prefer: count=exact` probes +
  Storage API, cross-checked against every `.from('…')` / model `fromJson` key
  in `lib/`.
- **Companion migration:** `supabase/2026-06-09_production_upgrade.sql`
  (ready to apply in the SQL editor; idempotent, non-destructive).

## 1. Verdict at a glance

| Area | Status |
|---|---|
| All 14 tables the app queries | ✅ exist |
| Storage buckets | ⚠️ `avatars`, `photos` existed; **`milestones` was missing — created during this audit** |
| `ai_cache` writes | ❌ **broken in production** (3 schema mismatches, fails silently) |
| `sleeps.quality` / `sleeps.wake_count` | ⚠️ read by the model, missing in DB (always null) |
| Indexes on hot log queries | ⚠️ none defined in repo migrations; recommended set in new migration |
| RLS | ⚠️ repo migrations only cover 4 of 14 tables; hardening included in new migration |
| RPC functions | ✅ none used by the app (`user_has_baby_access`, `is_baby_owner` are policy helpers only) |

## 2. Live tables, columns, and row counts

Row counts are exact (service-role `Prefer: count=exact`, 2026-06-09).

### babies — 2 rows
`id (uuid PK)`, `user_id* (uuid)`, `name* (text)`, `date_of_birth* (date)`, `gender (text)`, `photo_url (text)`, `created_at (timestamptz)`, `owner_id (uuid)`

### profiles — 4 rows
`id (uuid PK)`, `email (text)`, `display_name (text)`, `avatar_url (text)`, `phone (text)`, `bio (text)`, `created_at (timestamptz)`

### baby_shares — 4 rows
`id (uuid PK)`, `baby_id* (FK babies)`, `user_id*`, `role*` (check: owner|parent|logger|viewer per `fix_role_check.sql`), `invited_by`, `created_at`

Live data: 3 shares on "Dezhay Allies" (2 owners + 1 logger), 1 owner share on "Methuli". Both babies have `owner_id` set. Consistent.

### baby_invites — 3 rows
`id (uuid PK)`, `baby_id* (FK)`, `invited_by*`, `token*`, `role*`, `expires_at*`, `used_by`, `used_at`, `created_at`

### baby_medications — 1 row
`id (uuid PK)`, `baby_id* (FK)`, `name*`, `default_dosage`, `created_by*`, `created_at*`

### feedings — 158 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `type*`, `duration_minutes (int)`, `amount_ml (int)`, `notes`, `logged_at (timestamptz)`, `created_at`

### diapers — 22 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `type*`, `color`, `notes`, `logged_at`, `created_at`

### sleeps — 5 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `start_time* (timestamptz)`, `end_time`, `duration_minutes (int)`, `notes`, `created_at`
**Missing vs app model:** `quality`, `wake_count` (see §4.2).

### tummy_times — 1 row
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `start_time*`, `end_time`, `duration_minutes`, `notes`, `created_at`

### growth — 0 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `weight_kg (numeric)`, `height_cm (numeric)`, `head_cm (numeric)`, `measured_at`, `notes`, `created_at`

### health_logs — 2 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `temperature_c (numeric)`, `medication`, `dosage`, `symptoms`, `notes`, `logged_at`, `created_at`

### milestones — 122 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `category*`, `title*`, `description`, `achieved (bool)`, `achieved_at`, `expected_age_months (int)`, `photo_url`, `created_at`
(122 = the default seed set × 2 babies; seeding in `milestone_provider.dart` works.)

### photos — 11 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id*`, `url*`, `caption`, `taken_at`, `created_at`

### ai_cache — 6 rows
`id (uuid PK)`, `baby_id* (FK)`, `user_id* (NOT NULL, no default)`, `cache_key*`, `response* (jsonb)`, `cached_date* (date)`, `created_at`
**Missing vs app:** `ai_type` (see §4.1). Newest row is **2026-03-09** — writes have failed silently for 3 months.

## 3. Storage buckets

| Bucket | Status | Config |
|---|---|---|
| `avatars` | existed | public, 2 MB limit, image/jpeg+png+webp+gif. Used by `profile_provider.dart` and `baby_provider.dart`. |
| `photos` | existed | public, 5 MB limit, same mime types. Used by `photo_provider.dart`. |
| `milestones` | **missing → created 2026-06-09 by this audit** | public, 5 MB limit, image/jpeg+png+webp+gif (mirrors `photos`). |

Note: no Dart code currently uploads to `milestones` — `MilestoneActions.updatePhoto()`
exists in `lib/providers/milestone_provider.dart` but has no caller, so the
milestone-photo feature is unwired in the app. The bucket is now ready for it.

## 4. Code ↔ DB mismatches

### 4.1 `ai_cache` writes are broken (silent failure) — HIGH
`lib/services/ai_service.dart:76` upserts
`{ baby_id, cache_key, ai_type, response, cached_date, created_at }` inside a
`try { … } catch (_) {}`. Three independent failures:

1. **`ai_type` column does not exist** → PostgREST rejects the whole row (PGRST204).
2. **`user_id` is NOT NULL with no default** and the app never sends it.
3. **`cached_date` is `date`** but the app sends `'YYYY-MM-DD-am'`/`'-pm'` — an invalid date literal.

Consequence: every AI response (insights, weekly summary, sleep prediction) is
re-generated on every load — extra Groq API spend and latency; the cache table
has been frozen since 2026-03-09. The migration fixes all three (adds `ai_type`,
defaults `user_id` to `auth.uid()`, widens `cached_date` to `text`).

Additional code-side note: the upsert passes no `onConflict`, so it only
conflicts on the PK and will simply insert new rows. Harmless, but if true
upsert semantics are wanted, dedupe the two legacy rows
(`(baby, 'insights')` exists twice with different `cached_date`), add a unique
index on `(baby_id, cache_key)`, and pass `onConflict: 'baby_id,cache_key'`.
The audit deliberately did not delete the legacy rows (non-destructive policy).

### 4.2 `sleeps.quality` / `sleeps.wake_count` — LOW
`lib/models/sleep_session.dart:46-47` reads `json['quality']` and
`json['wake_count']`; neither column exists, so both fields are always null.
No provider writes them either, so nothing crashes — but the model fields are
dead. Migration adds both columns (`text`, `integer`) so the feature can be wired.

### 4.3 Everything else matches
All other model `fromJson` keys (`logged_at`, `measured_at`, `taken_at`,
`start_time`/`end_time`, `photo_url` on babies & milestones, `phone`/`bio` on
profiles, invite token fields, medication fields) exist in the live schema with
compatible types, verified against sample rows. No `.rpc()` calls exist in
`lib/`, so no database functions are required by the client beyond the two RLS
helper functions.

## 5. Recommended indexes (all in the new migration, `IF NOT EXISTS`)

Every log provider runs `eq('baby_id', X)` + `order(ts desc)` and the
stats/badges/weekly-summary providers add `gte(ts, …)` range filters — a
composite `(baby_id, ts DESC)` index serves all of them:

| Table | Index |
|---|---|
| feedings | `(baby_id, logged_at DESC)` |
| diapers | `(baby_id, logged_at DESC)` |
| health_logs | `(baby_id, logged_at DESC)` |
| sleeps | `(baby_id, start_time DESC)` |
| tummy_times | `(baby_id, start_time DESC)` |
| growth | `(baby_id, measured_at DESC)` |
| photos | `(baby_id, taken_at DESC)` |
| milestones | `(baby_id, expected_age_months)` |
| ai_cache | `(baby_id, cache_key)` (non-unique — legacy dupes exist) |
| baby_shares | `(user_id, baby_id)` and `(baby_id)` — these back **every RLS check** via `user_has_baby_access()` |
| baby_invites | `(token)` |
| baby_medications | `(baby_id)` |

At current row counts (≤158) none of these matter for speed yet, but
`baby_shares` indexes are on the RLS hot path for every query the app makes,
so they are the cheapest insurance available.

## 6. RLS posture

Per the four repo migration files:

| Table | Covered by repo migrations? | Policy summary |
|---|---|---|
| babies | ✅ `fix_rls_and_sharing.sql` + `fix_rls_recursion.sql` | select: any sharer; insert: `auth.uid() = user_id`; update: owner (via `is_baby_owner`); delete: `owner_id = auth.uid()` |
| baby_shares | ✅ same | select: any sharer; insert/update/delete: owner (or self-insert when accepting invite) |
| profiles | ✅ `fix_rls_and_sharing.sql` | select: self + co-sharers; update: self. **No insert policy** (assumes a signup trigger creates rows) |
| baby_medications | ✅ `add_baby_medications.sql` | members read; owners insert/delete |
| feedings, diapers, sleeps, growth, health_logs, milestones, tummy_times, photos, ai_cache, baby_invites | ❌ **not in any repo migration** | Whatever was clicked together in the dashboard (unverifiable with a service key, which bypasses RLS). The app demonstrably reads/writes these as multiple sharer accounts, so *some* policies exist — but they are not in version control. |
| storage.objects | ⚠️ `avatars` only | upload/update own folder, public read. **No repo policies for `photos` or `milestones` buckets.** |

The new migration adds version-controlled, share-based CRUD policies for all
ten uncovered tables (built on the existing `user_has_baby_access()` helper,
so no recursion) plus storage policies for the `photos` and `milestones`
buckets. Policies are OR'd in Postgres, so applying them alongside any
existing dashboard policies can only widen access to the intended
"everyone on the baby's share list" model — it cannot lock anyone out.

## 7. Actions taken during this audit

1. **Created** the `milestones` storage bucket (public, 5 MB, image mime types)
   via the Storage API — it was the only missing object the app/prompt expects.
2. **Wrote** `supabase/2026-06-09_production_upgrade.sql` (not applied — SQL
   cannot be executed through PostgREST with a service key). Apply it in the
   Supabase SQL editor; it is idempotent and non-destructive. Run
   `fix_rls_and_sharing.sql` first on a fresh project (it defines
   `user_has_baby_access`).
3. **No data was modified or deleted.** No git commits were made.

## 8. Follow-ups for the app code (not done here)

- `ai_service.dart`: after applying the migration the cache will work as-is;
  optionally pass `user_id` explicitly and `onConflict: 'baby_id,cache_key'`
  (after deduping legacy rows + unique index) for real upsert semantics.
- Wire up `MilestoneActions.updatePhoto()` to an image picker that uploads to
  the new `milestones` bucket.
- Wire `quality` / `wake_count` into the sleep logging UI, or delete the dead
  model fields.
