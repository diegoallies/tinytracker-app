# TinyTrack 🍼

AI-powered baby tracking app for the Allies family — feeds, sleep, nappies, growth, milestones, and the full nanny care-pack workflow, in one place.

Built with Flutter + Supabase. Runs on iOS and Android.

## Features

**Daily tracking**
- Feedings (breast/bottle/solids) with timer, feed quality (1–5) and spit-up flag
- Diapers with poop colour + stool type (1–7) and AI colour analysis
- Sleep sessions with live timer, backdating, and wake predictions
- Tummy time with daily goal, growth (WHO percentile charts), health logs, photos, milestones

**Care Pack** (the family's paper tracking pack, digitised)
- Reflux tracker — severity 1–5 scale, triggers, 14-day view, weekly trend
- Daily journal — mood, cramps & gas scales, activities and firsts
- Weekly report by age — stage-specific milestone checklists with auto-computed
  numbers from the logs; share to parents as PDF or text
- Monthly milestone review — the deep checklist done on the 4th of each month
- Care guide — red flags, reference scales, emergency contact sheet with tap-to-call

**Intelligence**
- "Next up" predictions: next feeding and nap windows learned from the baby's own patterns
- AI insights, daily summaries, sleep predictions and poop analysis (Groq / Llama 3.3)
- Pattern badges and weekly summaries

**Family sharing**
- Invite caregivers by link with owner / logger / viewer roles
- OS-scheduled feeding reminders, dark mode (night feeds!), offline banner, PDF export

## Setup

1. Flutter SDK ^3.11, then `flutter pub get`
2. Create `.env` in the project root:
   ```
   SUPABASE_URL=...
   SUPABASE_ANON_KEY=...
   GROQ_API_KEY=...
   ```
3. Apply the SQL in `supabase/` to your Supabase project (files are dated and
   idempotent — run them in order in the SQL editor).
4. `flutter run`

## Architecture

```
lib/
├── app/router.dart        # GoRouter: auth redirect + shell with bottom nav
├── config/                # theme (Material 3 + AppPalette), design tokens, env
├── models/                # plain Dart models, manual JSON mapping
├── providers/             # Riverpod: one file per domain + actions classes
├── services/              # supabase, auth, AI (Groq), notifications, predictions
├── screens/               # one folder per screen
├── widgets/               # shared components (cards, dialogs, skeletons, …)
└── utils/                 # extensions, haptics, care-pack/WHO static data
```

- **State**: Riverpod `FutureProvider`s per query + static `*Actions` classes for writes
- **Theming**: everything flows from `Theme.of(context)` / `context.palette` —
  light/dark via `ThemeExtension`, design tokens in `config/design_tokens.dart`
- **DB**: Supabase Postgres with RLS (share-based access via `baby_shares`),
  storage buckets for avatars/photos/milestones
- **Docs**: `docs/CHANGELOG-claude.md` (change log), `docs/SUPABASE-AUDIT.md` (DB audit)

## Tests

```
flutter test
```

Unit tests cover the prediction engine (`test/prediction_service_test.dart`).
