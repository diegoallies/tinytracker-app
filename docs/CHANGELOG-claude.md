# TinyTrack — Production-Grade Overhaul Changelog

Overnight upgrade run, 2026-06-09 → 2026-06-10. Goal: keep the existing skeleton (Riverpod + GoRouter + Supabase), upgrade everything to a premium, production-grade standard.

Process: small working increments, committed and pushed continuously. Self-review every 5 commits (analyze + diff re-read).

## Plan

1. Clean analyzer baseline (45 info issues → 0)
2. Design-system foundation: spacing/radius tokens, shared dialogs/snackbars/components
3. Supabase schema audit + DB improvements (indexes, RLS, missing tables)
4. Premium polish per screen group: auth/splash/onboarding → dashboard → tracking screens → data screens → profile/settings
5. Robustness: offline banner, retry states, validation bounds
6. Docs: README rewrite, this changelog, final full-diff review

## Changes

(appended as work lands; one entry per commit)

### 1. Clean analyzer baseline (45 → 0 issues)
- `dart fix --apply` resolved 38 auto-fixable lints (wildcard underscores, unnecessary `this.`, string interpolation, dangling doc comment).
- Manual fixes: splash screen now re-checks `mounted` after the SharedPreferences await before navigating; 4 deprecated `withOpacity` calls → `withValues(alpha:)`; photo viewer delete uses `context.mounted` guard.
- Also: autonomous-session setup — `.claude/settings.local.json` gitignored, `docs/CHANGELOG-claude.md` created.

### 2. Design-system foundation
- New `lib/config/design_tokens.dart`: `AppSpacing` (spacing scale + screen/card/sheet padding presets), `AppRadius` (radius scale + const BorderRadius presets), `AppMotion` (durations/curves), `AppShadows` (brightness-aware card/floating shadows).
- `theme.dart` upgraded to a full Material 3 component theme: dialogs, bottom sheets (drag handle, rounded top), snackbars (floating, dark pill), chips, switches, FAB, list tiles, progress indicators, text buttons, dividers — all consistent with tokens. Added `border` color to `AppPalette` (light `#EDE8F4` / dark `#2E2740`), iOS/Android page transitions, InkSparkle splash, tighter letter-spacing on headlines, 52px buttons with disabled states. AppPalette/AppColors stay const + `Theme.of(context)`-driven (per repo memory).
- New `lib/widgets/common/app_dialogs.dart`: `showConfirmDialog` / `showDeleteDialog` — one premium confirmation dialog (icon badge, centered copy, side-by-side actions, haptics) to replace every hand-rolled AlertDialog.
- `extensions.dart`: snackbars rebuilt — themed dark pill with colored leading icon, `showErrorSnackBar(onRetry:)` support, auto-dismiss of previous snackbar.

### 3. Supabase production audit (docs/SUPABASE-AUDIT.md)
- Audited the live database against the code. All 14 tables exist; found and fixed: **missing `milestones` storage bucket (created live)**.
- Found a high-impact silent bug: `ai_cache` writes have failed since March (missing `ai_type` column, NOT-NULL `user_id` omitted, wrong date format) — swallowed by `catch (_) {}`, so every AI insight re-hits Groq. Code fix queued.
- Found `sleeps.quality`/`wake_count` referenced in code but absent in DB (silently null), zero indexes on hot `(baby_id, time)` paths, and 10 tables whose RLS only lives in the dashboard.
- Wrote idempotent `supabase/2026-06-09_production_upgrade.sql` (missing columns, 13 indexes, versioned RLS policies, storage policies) — **needs a one-time run in the Supabase SQL editor**.

### 4. Smart predictions engine ("what's next")
- New `lib/services/prediction_service.dart`: pure-Dart pattern engine — median-gap prediction with outlier filtering (double-logs, overnight stretches), day/night-aware bucketing, and a confidence score (sample size + regularity). Nap prediction works on awake windows (wake → next sleep start).
- New `lib/providers/prediction_provider.dart`: `nextFeedingPredictionProvider` / `nextNapPredictionProvider` over the last 7 days; failures degrade to null, never break a screen; no nap prediction while a sleep session is active.
- New `test/prediction_service_test.dart`: 8 unit tests, all green. Dashboard "Next up" card lands with the dashboard polish.
