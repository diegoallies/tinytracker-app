# TinyTracker Flutter App - Implementation Plan

> Full Flutter replication of the TinyTrack Next.js PWA

---

## Phase 0: Project Setup & Dependencies

### 0.1 - pubspec.yaml Dependencies
```yaml
dependencies:
  # Core
  flutter_riverpod: ^2.5.0        # State management (replaces Zustand + React Query)
  go_router: ^14.0.0              # Routing (replaces Next.js App Router)

  # Supabase
  supabase_flutter: ^2.8.0        # Supabase client (auth, DB, storage, realtime)

  # UI & Animation
  flutter_animate: ^4.5.0         # Animations (replaces Framer Motion)
  google_fonts: ^6.2.0            # Typography
  lucide_icons: ^0.257.0          # Icons (same as web app)
  shimmer: ^3.0.0                 # Loading skeletons
  cached_network_image: ^3.4.0    # Image caching

  # Charts
  fl_chart: ^0.69.0               # Charts (replaces Recharts)

  # Data & Storage
  shared_preferences: ^2.3.0      # Local preferences
  flutter_secure_storage: ^9.2.0  # Secure token storage
  hive_flutter: ^1.1.0            # Offline data cache

  # Media
  image_picker: ^1.1.0            # Photo capture/selection
  photo_view: ^0.15.0             # Fullscreen photo viewer with pinch-zoom

  # PDF
  pdf: ^3.11.0                    # PDF generation (replaces jsPDF)
  printing: ^5.13.0               # PDF preview/share

  # Notifications
  flutter_local_notifications: ^18.0.0

  # Utilities
  intl: ^0.19.0                   # Date formatting
  timeago: ^3.7.0                 # Relative time ("2 hours ago")
  uuid: ^4.4.0                    # UUID generation
  url_launcher: ^6.3.0            # External links
  share_plus: ^10.0.0             # Share functionality
  connectivity_plus: ^6.0.0       # Online/offline detection
  flutter_dotenv: ^5.1.0          # Environment variables
```

### 0.2 - Project Structure
```
lib/
├── main.dart                     # App entry point, Supabase init, theme
├── app/
│   └── router.dart               # GoRouter configuration (all routes)
├── config/
│   ├── theme.dart                # TinyTrack theme (colors, text styles, card shapes)
│   ├── constants.dart            # API URLs, cache durations, etc.
│   └── env.dart                  # Environment variables wrapper
├── models/                       # Data models (freezed or manual)
│   ├── baby.dart
│   ├── feeding.dart
│   ├── diaper.dart
│   ├── sleep_session.dart
│   ├── growth.dart
│   ├── milestone.dart
│   ├── health_log.dart
│   ├── tummy_time.dart
│   ├── photo.dart
│   ├── profile.dart
│   ├── baby_share.dart
│   ├── baby_invite.dart
│   └── ai_cache.dart
├── providers/                    # Riverpod providers
│   ├── auth_provider.dart        # Auth state, login/logout
│   ├── baby_provider.dart        # Current baby selection + baby list
│   ├── feeding_provider.dart     # Feeding CRUD + queries
│   ├── diaper_provider.dart      # Diaper CRUD + queries
│   ├── sleep_provider.dart       # Sleep CRUD + queries
│   ├── growth_provider.dart      # Growth CRUD + queries
│   ├── milestone_provider.dart   # Milestone CRUD + queries
│   ├── health_provider.dart      # Health log CRUD
│   ├── tummy_time_provider.dart  # Tummy time CRUD
│   ├── photo_provider.dart       # Photo CRUD + upload
│   ├── stats_provider.dart       # Dashboard stats (today's counts)
│   ├── activity_provider.dart    # Activity feed (last 24h)
│   ├── ai_provider.dart          # AI insights, summaries, predictions
│   ├── share_provider.dart       # Baby sharing & invites
│   ├── profile_provider.dart     # User profile
│   └── connectivity_provider.dart # Online/offline state
├── services/                     # Business logic & API calls
│   ├── supabase_service.dart     # Supabase client singleton
│   ├── auth_service.dart         # Auth operations
│   ├── ai_service.dart           # AI API calls (insights, sleep-predict, etc.)
│   ├── export_service.dart       # PDF export generation
│   ├── notification_service.dart # Local notifications
│   ├── cache_service.dart        # Offline cache with Hive
│   └── who_growth_data.dart      # WHO percentile data
├── screens/                      # Full-page screens
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── dashboard/
│   │   └── dashboard_screen.dart
│   ├── feeding/
│   │   └── feeding_screen.dart
│   ├── diaper/
│   │   └── diaper_screen.dart
│   ├── sleep/
│   │   └── sleep_screen.dart
│   ├── growth/
│   │   └── growth_screen.dart
│   ├── health/
│   │   └── health_screen.dart
│   ├── milestones/
│   │   └── milestones_screen.dart
│   ├── tummy_time/
│   │   └── tummy_time_screen.dart
│   ├── photos/
│   │   └── photos_screen.dart
│   ├── summary/
│   │   └── summary_screen.dart
│   ├── export/
│   │   └── export_screen.dart
│   ├── profile/
│   │   └── profile_screen.dart
│   ├── baby/
│   │   └── baby_screen.dart
│   ├── invites/
│   │   └── invites_screen.dart
│   └── more/
│       └── more_screen.dart
├── widgets/                      # Reusable widgets
│   ├── layout/
│   │   ├── app_scaffold.dart     # Scaffold with bottom nav
│   │   ├── bottom_nav_bar.dart   # Custom bottom nav (6 items)
│   │   └── page_transition.dart  # Route transition animations
│   ├── common/
│   │   ├── animated_card.dart    # Card with entrance animation
│   │   ├── animated_list_item.dart
│   │   ├── count_up.dart         # Animated number counter
│   │   ├── success_animation.dart
│   │   ├── loading_skeleton.dart # Shimmer loading
│   │   ├── empty_state.dart      # Empty state with icon + CTA
│   │   ├── offline_banner.dart   # Offline indicator
│   │   ├── night_mode_toggle.dart
│   │   └── baby_selector.dart    # Baby dropdown
│   ├── dashboard/
│   │   ├── stats_card.dart       # Stats card (feeds today, diapers, etc.)
│   │   ├── quick_actions.dart    # Quick action buttons
│   │   └── activity_feed.dart    # Activity timeline
│   ├── ai/
│   │   ├── smart_insights.dart   # 3-insight carousel
│   │   ├── sleep_predictor.dart
│   │   ├── growth_ai_analysis.dart
│   │   ├── feeding_alert.dart
│   │   ├── poop_color_info.dart
│   │   └── daily_summary_widget.dart
│   ├── feeding/
│   │   ├── feeding_form.dart     # Feeding log form
│   │   ├── feeding_timer.dart    # Breastfeeding timer
│   │   └── feeding_history.dart  # Recent feedings list
│   ├── diaper/
│   │   ├── diaper_form.dart
│   │   └── poop_color_picker.dart
│   ├── sleep/
│   │   ├── sleep_form.dart
│   │   └── sleep_timer.dart
│   ├── growth/
│   │   ├── growth_form.dart
│   │   └── growth_chart.dart     # WHO percentile chart
│   ├── health/
│   │   ├── temperature_form.dart
│   │   └── medication_form.dart
│   ├── milestones/
│   │   ├── milestone_card.dart
│   │   └── milestone_category_tabs.dart
│   ├── photos/
│   │   ├── photo_grid.dart
│   │   └── photo_viewer.dart     # Fullscreen with swipe
│   └── charts/
│       ├── feeding_chart.dart
│       ├── sleep_chart.dart
│       └── growth_percentile_chart.dart
└── utils/
    ├── date_utils.dart           # Date helpers, timezone, day ranges
    ├── validators.dart           # Form validation
    ├── extensions.dart           # Dart extensions
    └── milestone_data.dart       # Predefined milestone templates
```

### 0.3 - Environment Setup
- `.env` file with: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GROQ_API_KEY`
- Same Supabase project as web app (shared database)
- No backend changes needed - Flutter talks directly to Supabase + Groq

---

## Phase 1: Core Infrastructure (Foundation)

### 1.1 - Theme & Design System
Replicate the exact TinyTrack visual identity:
- **Colors**: Primary purple `#9b72cf`, pastels (purple, blue, pink, green, yellow), surface `#faf8fc`, card white, text `#2d2640`, muted `#8b85a0`
- **Typography**: System font with consistent sizing (match web)
- **Cards**: `borderRadius: 20`, white background, subtle shadow
- **Buttons**: `borderRadius: 12`, min height 48px (touch target), primary purple
- **Inputs**: `borderRadius: 12`, surface background, pastel-purple border, focus ring
- **Modals**: Bottom sheet on mobile, slide up with backdrop blur

### 1.2 - Supabase Client & Auth
- Initialize Supabase with `supabase_flutter`
- Auth flow: email/password login & register (match web forms exactly)
- OAuth support (Google, Apple for mobile)
- Session persistence with secure storage
- Auto-refresh tokens
- Auth state listener → redirect to login/dashboard

### 1.3 - Router & Navigation
- GoRouter with auth redirect guard
- Bottom navigation bar: Home, Feed, Diaper, Sleep, More (with profile avatar)
- Page transitions: fade + slide (100ms, match web)
- Deep link support for invite URLs

### 1.4 - State Management with Riverpod
- `authProvider` - StreamProvider watching Supabase auth state
- `currentBabyProvider` - Selected baby from baby_shares
- `babyStoreProvider` - Baby ID, name, gender, DOB (replaces Zustand store)
- All data providers auto-refresh on baby change

---

## Phase 2: Data Models & CRUD

### 2.1 - Models (1:1 with DB schema)
Each model maps directly to the Supabase table:
- `Baby` - id, userId, ownerId, name, dateOfBirth, gender, photoUrl
- `Feeding` - id, babyId, userId, type (breast_left/right/bottle/solids), durationMinutes, amountMl, notes, loggedAt, deletedAt
- `Diaper` - id, babyId, userId, type (wet/dirty/both), color (yellow/green/brown/black/red/white), notes, loggedAt, deletedAt
- `SleepSession` - id, babyId, userId, startTime, endTime, durationMinutes, quality, wakeCount, environment (Map), deletedAt
- `Growth` - id, babyId, userId, weightKg, heightCm, headCm, measuredAt, notes
- `Milestone` - id, babyId, userId, category, title, description, achieved, achievedAt, expectedAgeMonths, photoUrl
- `HealthLog` - id, babyId, userId, temperatureC, medication, dosage, symptoms, notes, loggedAt
- `TummyTime` - id, babyId, userId, startTime, endTime, durationMinutes, notes
- `Photo` - id, babyId, userId, url, caption, takenAt, deletedAt
- `Profile` - id, email, displayName, avatarUrl, phone, bio
- `BabyShare` - id, babyId, userId, role (owner/logger/viewer)
- `BabyInvite` - id, babyId, token, role, expiresAt, usedBy

### 2.2 - Providers (CRUD for each entity)
Each provider handles:
- **Fetch list** (with date filtering, soft-delete exclusion)
- **Fetch single** by ID
- **Create** (insert + return)
- **Update** (partial update)
- **Soft delete** (set deleted_at)
- **Optimistic updates** (instant UI feedback)
- Auto-invalidation on mutations

### 2.3 - Offline Support
- Hive boxes for each entity type
- Queue mutations when offline → sync when back online
- `connectivityProvider` watches network state
- Offline banner widget shown when disconnected

---

## Phase 3: Screens (Page-by-Page Replication)

### 3.1 - Auth Screens
**Login Screen** (`/login`)
- Email + password fields
- "Log In" button (primary purple)
- "Don't have an account? Register" link
- OAuth buttons (Google, Apple)
- Error handling with toast messages

**Register Screen** (`/register`)
- Email + password + confirm password
- "Create Account" button
- "Already have an account? Log In" link
- Auto-login after successful registration

### 3.2 - Dashboard Screen (`/dashboard`)
The main hub - most complex screen:
- **Header**: Baby name + age, baby selector dropdown
- **Stats Row**: 4 cards showing today's counts:
  - Feedings (bottle icon + count)
  - Diapers (droplet icon + count)
  - Sleep (moon icon + total hours)
  - Last Activity (clock icon + relative time)
- **Smart Insights**: Horizontal carousel of 3 AI insights (auto-fetched, cached 2x daily)
- **Quick Actions**: Grid of 8 action buttons → navigate to each tracking screen
  - Feed, Diaper, Sleep, Growth, Health, Milestones, Tummy Time, Photos
- **Activity Feed**: Last 24h timeline with icons, times, user attribution
- **Daily Summary Widget**: Compact AI summary card
- **Sleep Predictor**: "Next sleep predicted at..." card
- **Feeding Alert**: Warning card if unusual pattern detected

### 3.3 - Feeding Screen (`/feeding`)
- **Type selector**: 4 toggle buttons (Left Breast, Right Breast, Bottle, Solids)
- **Timer** (breast): Start/stop with elapsed time display, pulsing animation
- **Amount input** (bottle): ML input with +/- buttons
- **Notes**: Optional text field
- **Save button**: Creates feeding record
- **History**: Scrollable list of recent feedings with edit/delete
- **AI Feeding Alert**: Shown if pattern anomaly detected

### 3.4 - Diaper Screen (`/diaper`)
- **Type selector**: 3 toggle buttons (Wet, Dirty, Both)
- **Poop color picker**: 6 color circles (yellow, green, brown, black, red, white) - only shown for dirty/both
- **Poop Color Info**: AI analysis of selected color's health significance
- **Notes**: Optional text field
- **Save button**
- **History**: Recent diapers with color indicators

### 3.5 - Sleep Screen (`/sleep`)
- **Timer**: Large start/stop button with elapsed time
- **Timer animation**: Pulsing ring while active
- **Quality selector**: 4 options (Excellent, Good, Fair, Poor)
- **Wake count**: Numeric stepper
- **Notes**: Optional
- **Save button**: Creates sleep record with calculated duration
- **History**: Recent sleep sessions with duration bars
- **Sleep Predictor**: AI prediction of next sleep time

### 3.6 - Growth Screen (`/growth`)
- **Input form**: Weight (kg), Height (cm), Head circumference (cm) - all decimal
- **Date picker**: Measurement date
- **Save button**
- **Growth Chart**: Line chart with WHO percentile bands
  - Toggle between weight, height, head
  - Shows percentile position
  - Gender-specific data (boys blue, girls pink)
- **AI Growth Analysis**: Percentile interpretation and trend insights
- **History**: Measurement log table

### 3.7 - Health Screen (`/health`)
- **Tabs**: Temperature | Medication
- **Temperature tab**:
  - Temperature input (celsius) with fever indicator (>37.5)
  - Symptoms multi-select or text
  - Notes
- **Medication tab**:
  - Medication name
  - Dosage
  - Notes
- **Save button** (per tab)
- **History**: Combined health log with icons

### 3.8 - Milestones Screen (`/milestones`)
- **Category tabs**: Motor, Social, Language, Cognitive
- **Milestone list**: Pre-defined + custom milestones
  - Each card: title, expected age, achieved checkbox, date achieved, photo
  - Toggle achieved → records date
  - Photo upload option for milestone moment
- **Progress indicator**: X of Y achieved per category
- **Add custom milestone** button

### 3.9 - Tummy Time Screen (`/tummy-time`)
- **Timer**: Start/stop with elapsed time
- **Daily goal progress**: Circular progress toward 30-min goal
- **Notes**: Optional
- **Save button**
- **Today's sessions**: List with durations
- **Weekly summary**: Bar chart of daily totals

### 3.10 - Photos Screen (`/photos`)
- **Photo grid**: 3-column masonry-style grid
- **Add photo**: Camera or gallery picker
- **Caption input**: On upload
- **Fullscreen viewer**: Swipe between photos, pinch-to-zoom
- **Delete**: Swipe or long-press to delete
- **Collage PDF**: Generate photo collage PDF for sharing
- **Infinite scroll**: Load more as user scrolls

### 3.11 - Summary Screen (`/summary`)
- **Today's Summary**: AI-generated daily summary
- **Comparison cards**: Today vs Yesterday vs Weekly Average
  - Feedings count + total ml
  - Diapers count by type
  - Sleep total hours
  - Growth latest
- **Charts**: Mini sparklines for each category
- **Pattern alerts**: Any anomalies detected

### 3.12 - Export Screen (`/export`)
- **Date range picker**: Last 7 days / 14 days / 30 days / custom
- **Category toggles**: Select which data to include
- **Generate PDF button**: Creates styled PDF report
- **Share/Save**: Share sheet or save to device
- PDF styling: Purple theme, tables, charts

### 3.13 - Profile Screen (`/profile`)
- **Avatar**: Tap to change (camera/gallery), upload to Supabase storage
- **Display name**: Editable
- **Email**: Read-only
- **Phone**: Editable
- **Bio**: Editable textarea
- **Save button**
- **Logout button**

### 3.14 - Baby Screen (`/baby`)
- **Create/Edit baby**: Name, DOB (date picker), gender (boy/girl/other), photo
- **Sharing section** (owner only):
  - Current shares list with roles
  - Create invite link (generates token)
  - Copy invite link
  - Remove share access
- **Delete baby** (owner only, with confirmation)

### 3.15 - Invites Screen (`/invites`)
- **Pending invites**: List of received invites
- **Accept/Decline**: Action buttons
- **Deep link handler**: Open app from invite URL → auto-accept

### 3.16 - More Screen (`/more`)
- **Grid of feature cards**: Growth, Health, Milestones, Tummy Time, Photos, Summary, Export
- **Night Mode toggle**: Red-tinted overlay for nighttime feeds
- **Settings**: Notification preferences, units (metric/imperial), etc.

---

## Phase 4: AI Integration

### 4.1 - AI Service
- Direct Groq API calls from the app (or proxy through Supabase Edge Functions for security)
- Model: llama-3.3-70b with fallback to llama-3.1-8b
- Same prompt templates as web API routes
- Response caching in `ai_cache` table (2x daily: AM/PM)

### 4.2 - AI Features
1. **Smart Insights** - 3 weekly pattern insights (carousel)
2. **Daily Summary** - Today vs yesterday vs weekly comparison
3. **Sleep Predictor** - Next sleep time prediction
4. **Feeding Alert** - Unusual feeding pattern detection
5. **Poop Analyzer** - Color health significance
6. **Growth Analyzer** - WHO percentile interpretation

### 4.3 - Cache Strategy
- Check `ai_cache` table first (matching baby_id + type + period)
- Cache period: AM (before 3pm) / PM (after 3pm)
- On cache miss: call Groq API → store response → return
- Force refresh button for users

---

## Phase 5: Advanced Features

### 5.1 - Notifications
- Local notifications for:
  - Feeding reminders (configurable interval)
  - Sleep reminders
  - Medication reminders
- Schedule via `flutter_local_notifications`

### 5.2 - Night Mode
- Red-tinted color filter overlay
- Toggle via button in nav/settings
- Remembers state in SharedPreferences
- Reduces blue light for nighttime feeds

### 5.3 - Offline Mode
- Hive local database for offline data
- Queue mutations when offline
- Auto-sync when connectivity restored
- Visual indicator (offline banner)

### 5.4 - Multi-User Sharing
- Role-based access: owner (full), logger (add data), viewer (read-only)
- Invite link generation with 7-day expiry
- Deep link handling for invite acceptance
- Activity feed shows user attribution

### 5.5 - Animations (match web exactly)
- **Page transitions**: Fade + slide right (100ms)
- **Card entrance**: Stagger animation (each card delays 50ms)
- **Button press**: Scale down to 0.95
- **Timer pulse**: Opacity oscillation (2s cycle)
- **Loading**: Shimmer skeletons
- **Success**: Checkmark scale-in animation
- **Count up**: Animated number tween

---

## Phase 6: Polish & Platform-Specific

### 6.1 - iOS
- Safe area handling (notch, home indicator)
- Haptic feedback on button presses
- Native share sheet
- App Store icon & splash screen
- Apple Sign In

### 6.2 - Android
- Material You adaptive colors (optional)
- Edge-to-edge display
- Back gesture handling
- Google Sign In
- Play Store listing assets

### 6.3 - Performance
- Image caching with `cached_network_image`
- Lazy loading for lists
- Pagination for history lists
- Debounced search/filter inputs
- Minimize rebuilds with `select` on Riverpod providers

### 6.4 - Testing
- Unit tests for models, providers, services
- Widget tests for key screens
- Integration tests for auth flow, CRUD operations

---

## Implementation Order (Recommended)

```
Week 1: Phase 0 + Phase 1 (Setup, theme, auth, navigation)
Week 2: Phase 2 (Models, providers, CRUD)
Week 3: Phase 3.1-3.5 (Auth, Dashboard, Feeding, Diaper, Sleep)
Week 4: Phase 3.6-3.10 (Growth, Health, Milestones, Tummy Time, Photos)
Week 5: Phase 3.11-3.16 (Summary, Export, Profile, Baby, Invites, More)
Week 6: Phase 4 (AI Integration)
Week 7: Phase 5 (Notifications, Night Mode, Offline, Sharing, Animations)
Week 8: Phase 6 (Platform polish, testing, optimization)
```

---

## Color Reference (Exact Hex)

| Name           | Hex       | Usage                        |
|----------------|-----------|------------------------------|
| Primary        | `#9b72cf` | Buttons, accents, nav active |
| Pastel Purple  | `#e8d5f5` | Card accents, backgrounds    |
| Pastel Blue    | `#d5e8f5` | Sleep-related elements       |
| Pastel Pink    | `#f5d5e8` | Feeding-related elements     |
| Pastel Green   | `#d5f5e8` | Health/growth elements       |
| Pastel Yellow  | `#f5f0d5` | Diaper-related elements      |
| Surface        | `#faf8fc` | Page backgrounds             |
| Card           | `#ffffff` | Card backgrounds             |
| Text           | `#2d2640` | Primary text                 |
| Muted          | `#8b85a0` | Secondary text               |

---

## Key Architecture Decisions

1. **Riverpod over BLoC**: Simpler, less boilerplate, similar mental model to React hooks
2. **GoRouter over Navigator 2.0**: Declarative routing matching Next.js App Router
3. **Direct Supabase over custom backend**: Same API as web, no extra server needed
4. **Hive for offline**: Lightweight, fast, perfect for caching records
5. **fl_chart over syncfusion**: Open source, good enough for WHO growth charts
6. **flutter_animate**: Closest match to Framer Motion API style
7. **Bottom sheets over dialogs**: Match the web modal behavior on mobile

---

## Files to Reference from Web App

When implementing each screen, reference these web source files:

| Flutter Screen     | Web Source File                          |
|--------------------|------------------------------------------|
| Dashboard          | `src/app/dashboard/page.tsx`             |
| Feeding            | `src/app/feeding/page.tsx`               |
| Diaper             | `src/app/diaper/page.tsx`                |
| Sleep              | `src/app/sleep/page.tsx`                 |
| Growth             | `src/app/growth/page.tsx`                |
| Health             | `src/app/health/page.tsx`                |
| Milestones         | `src/app/milestones/page.tsx`            |
| Tummy Time         | `src/app/tummy-time/page.tsx`            |
| Photos             | `src/app/photos/page.tsx`                |
| Summary            | `src/app/summary/page.tsx`               |
| Export             | `src/app/export/page.tsx`                |
| Profile            | `src/app/profile/page.tsx`               |
| Baby               | `src/app/baby/page.tsx`                  |
| Nav Bar            | `src/components/NavBar.tsx`              |
| Smart Insights     | `src/components/SmartInsights.tsx`       |
| Activity Feed      | `src/components/ActivityFeed.tsx`        |
| AI endpoints       | `src/app/api/ai/*.ts`                    |
| WHO data           | `src/lib/who-growth-data.ts`             |
| Milestone data     | `src/lib/milestone-data.ts`              |
| Theme/colors       | `src/app/globals.css`                    |
