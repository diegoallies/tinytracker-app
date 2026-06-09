import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../widgets/layout/app_scaffold.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/feeding/feeding_screen.dart';
import '../screens/diaper/diaper_screen.dart';
import '../screens/sleep/sleep_screen.dart';
import '../screens/growth/growth_screen.dart';
import '../screens/health/health_screen.dart';
import '../screens/milestones/milestones_screen.dart';
import '../screens/tummy_time/tummy_time_screen.dart';
import '../screens/photos/photos_screen.dart';
import '../screens/summary/summary_screen.dart';
import '../screens/export/export_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/baby/baby_screen.dart';
import '../screens/invites/invites_screen.dart';
import '../screens/reflux/reflux_screen.dart';
import '../screens/journal/daily_journal_screen.dart';
import '../screens/weekly_report/weekly_report_screen.dart';
import '../screens/monthly_review/monthly_review_screen.dart';
import '../screens/care_guide/care_guide_screen.dart';
import '../screens/immunisations/immunisations_screen.dart';
import '../screens/more/more_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Shared RouteObserver for the shell navigator. Screens subscribe to this
/// to know when they become visible again after a sibling tab was popped
/// (e.g. dashboard listening for return from /sleep so it can refresh).
final shellRouteObserver = RouteObserver<PageRoute<dynamic>>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final isAuthenticated = SupabaseService.currentUser != null;
    final path = state.uri.toString();
    final isAuthRoute = path == '/login' || path == '/register';
    final isSplash = path == '/';

    // Don't redirect away from splash
    if (isSplash) return null;

    if (!isAuthenticated && !isAuthRoute) return '/login';
    if (isAuthenticated && isAuthRoute) return '/dashboard';
    return null;
  },
  routes: [
    // Splash screen
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    // Auth routes (no shell)
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),

    // Main app with bottom nav
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      observers: [shellRouteObserver],
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const DashboardScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/feeding',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const FeedingScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/diaper',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const DiaperScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/sleep',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SleepScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/more',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const MoreScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const ProfileScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/growth',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const GrowthScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/health',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const HealthScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/milestones',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const MilestonesScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/tummy-time',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const TummyTimeScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/photos',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const PhotosScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/summary',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SummaryScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/export',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const ExportScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/baby',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const BabyScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/invites',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: InvitesScreen(
              initialCode: state.uri.queryParameters['code'],
            ),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SettingsScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/reflux',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const RefluxScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/journal',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const DailyJournalScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/weekly-report',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const WeeklyReportScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/monthly-review',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const MonthlyReviewScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/care-guide',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const CareGuideScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
        GoRoute(
          path: '/immunisations',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const ImmunisationsScreen(),
            transitionsBuilder: _slideTransition,
          ),
        ),
      ],
    ),
  ],
);

Widget _fadeTransition(
    BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
  return FadeTransition(opacity: animation, child: child);
}

Widget _slideTransition(
    BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
  return SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
    child: FadeTransition(opacity: animation, child: child),
  );
}
