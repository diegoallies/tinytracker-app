import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics wrapper.
///
/// Two rules this file exists to enforce:
///
/// 1. **No health data ever leaves the device.** This is a baby health app, so
///    we log that a feed happened, never how much or when relative to anything.
///    No volumes, durations, weights, medication names, notes or free text.
///    Event params are limited to low-cardinality enums (`source`, `type`).
/// 2. **Nothing throws.** Analytics is never worth breaking a user flow over,
///    so every call is fire-and-forget and swallows its errors.
///
/// Debug builds don't report — see [init] — so local testing doesn't pollute
/// the dashboard.
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Navigator observer that logs `screen_view` automatically. Wired into
  /// `appRouter` in `lib/app/router.dart`.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// Where an action came from. The watch never talks to Supabase directly —
  /// every watch tap is forwarded to the phone through `WatchBridge` — so we
  /// tag the origin here rather than installing the Firebase watchOS SDK.
  static const sourcePhone = 'phone';
  static const sourceWatch = 'watch';

  static Future<void> init() async {
    try {
      // Debug builds would otherwise skew retention and funnel numbers.
      await _analytics.setAnalyticsCollectionEnabled(!kDebugMode);
    } catch (e) {
      debugPrint('analytics init failed: $e');
    }
  }

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('analytics event $name failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  /// Ties events to a stable id so retention cohorts work across devices.
  /// The Supabase user id is an opaque uuid, not personal data.
  static Future<void> setUser(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      debugPrint('analytics setUser failed: $e');
    }
  }

  /// 'owner' (parent) or 'logger' (nanny) — drives almost every behavioural
  /// difference in the app, so it's worth having as a segment.
  static Future<void> setRole(String role) async {
    try {
      await _analytics.setUserProperty(name: 'baby_role', value: role);
    } catch (e) {
      debugPrint('analytics setRole failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Funnel + retention
  // ---------------------------------------------------------------------------

  /// GA4 reserved name — populates the built-in signup funnel.
  static Future<void> logSignUp() => _log('sign_up', {'method': 'email'});

  /// GA4 reserved name — populates the built-in login report.
  static Future<void> logLogin() => _log('login', {'method': 'email'});

  static Future<void> logOnboardingComplete() =>
      _log('onboarding_complete');

  static Future<void> logBabyCreated() => _log('baby_created');

  static Future<void> logInviteSent() => _log('invite_sent');

  static Future<void> logInviteAccepted() => _log('invite_accepted');

  // ---------------------------------------------------------------------------
  // Core logging actions — counts only, never values
  // ---------------------------------------------------------------------------

  static Future<void> logFeed({String source = sourcePhone}) =>
      _log('feed_logged', {'source': source});

  static Future<void> logSleep({String source = sourcePhone}) =>
      _log('sleep_logged', {'source': source});

  static Future<void> logDiaper({String source = sourcePhone}) =>
      _log('diaper_logged', {'source': source});

  static Future<void> logMedication({String source = sourcePhone}) =>
      _log('medication_given', {'source': source});

  static Future<void> logWeeklyReportSubmitted() =>
      _log('weekly_report_submitted');

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  /// Whether users actually grant notification permission — worth knowing
  /// before blaming the send path for low delivery.
  static Future<void> logPushPermission({required bool granted}) =>
      _log('push_permission', {'granted': granted.toString()});

  /// A push was tapped. [type] is the payload's `type` field, e.g.
  /// `weekly_report_submitted`.
  static Future<void> logPushOpened(String type) =>
      _log('push_opened', {'type': type});
}
