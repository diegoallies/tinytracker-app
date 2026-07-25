import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/router.dart';
import 'analytics_service.dart';
import 'notification_prefs_sync.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Background isolate handler. Must be a top-level function annotated with
/// `vm:entry-point` or release builds tree-shake it away.
///
/// Deliberately empty: every push we send carries a `notification` block, so
/// the OS draws the banner itself without Dart running. It exists only so the
/// plugin has a registered handler and stops warning on every cold push.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {}

/// FCM remote push.
///
/// Tokens live in `device_tokens`, keyed by `(user_id, token)`, which the
/// `notify-report-submitted` edge function reads with the service role to reach
/// a baby's parents.
///
/// Everything here is guarded. Until the APNs key is uploaded to Firebase and
/// the Push Notifications capability is enabled in Xcode, iOS can't mint a
/// token — the app keeps working, push simply doesn't arrive.
class PushService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _syncing = false;

  /// Call once from `main()` after `Firebase.initializeApp`.
  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    await _requestPermission();

    // iOS suppresses foreground pushes unless presentation options are set
    // explicitly — without this, a push arriving while the app is open is
    // silently dropped rather than shown.
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('push presentation options failed: $e');
    }

    await _syncToken();
    _messaging.onTokenRefresh.listen(_storeToken);

    // The FCM token exists before login, but `device_tokens` rows need a
    // user_id — so re-store whenever a session appears, and drop the row on
    // sign-out so a shared device stops receiving the previous user's pushes.
    //
    // `initialSession` matters as much as `signedIn`: a returning user who is
    // already logged in only ever gets `initialSession`, so handling just
    // `signedIn` meant the token was never stored on any launch after the
    // first.
    SupabaseService.client.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          if (state.session != null) {
            _syncToken();
            // Feed/sleep reminders are sent server-side now, so the user's
            // thresholds have to exist in the database before the cron can act
            // on them.
            NotificationPrefsSync.reconcile();
          }
        case AuthChangeEvent.signedOut:
          _deleteToken();
        default:
          break;
      }
    });

    // Taps: a stream for warm starts, plus an explicit check for the cold start
    // where the push itself launched the app.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);

    // Foreground on Android draws nothing by default, so we render it through
    // the local-notifications plugin already used for reminders.
    FirebaseMessaging.onMessage.listen(_handleForeground);
  }

  static Future<void> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      final status = settings.authorizationStatus;
      await AnalyticsService.logPushPermission(
        granted: status == AuthorizationStatus.authorized ||
            status == AuthorizationStatus.provisional,
      );
    } catch (e) {
      debugPrint('push permission request failed: $e');
    }
  }

  /// APNs registration completes asynchronously after launch, so
  /// `getAPNSToken()` legitimately returns null for a second or two even when
  /// push is configured correctly. Poll briefly instead of giving up for the
  /// rest of the app session.
  static Future<String?> _awaitApnsToken() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final token = await _messaging.getAPNSToken();
      if (token != null) return token;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  /// Fetch the current FCM token and persist it against the logged-in user.
  static Future<void> _syncToken() async {
    // init() and the auth listener can both land here; without this the APNs
    // polling loop would stack.
    if (_syncing) return;
    _syncing = true;
    try {
      // On iOS the FCM token can't be minted until APNs hands us a device
      // token, which needs the Push Notifications capability plus an APNs key
      // in Firebase.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await _awaitApnsToken();
        if (apns == null) {
          debugPrint('push: no APNs token after 10s — check the Push '
              'Notifications capability and the APNs key in Firebase');
          return;
        }
      }
      final token = await _messaging.getToken();
      if (token != null) await _storeToken(token);
    } catch (e) {
      debugPrint('push token fetch failed: $e');
    } finally {
      _syncing = false;
    }
  }

  static Future<void> _storeToken(String token) async {
    final userId = SupabaseService.userId;
    if (userId == null || token.isEmpty) return;
    try {
      await SupabaseService.client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');
    } catch (e) {
      debugPrint('push token upsert failed: $e');
    }
  }

  /// Remove this device's token on sign-out. Without this, the next push for
  /// the previous user lands on a device someone else is now using.
  static Future<void> _deleteToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await SupabaseService.client
          .from('device_tokens')
          .delete()
          .eq('token', token);
    } catch (e) {
      debugPrint('push token delete failed: $e');
    }
  }

  static void _handleForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    // iOS already presents it via the options set in init(); showing it again
    // here would double up the banner.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    NotificationService.showRemoteNotification(
      title: notification.title ?? 'TinyTrack',
      body: notification.body ?? '',
    );
  }

  static void _handleTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (type == null) return;
    AnalyticsService.logPushOpened(type);
    switch (type) {
      case 'weekly_report_submitted':
        appRouter.go('/weekly-report');
      case 'feed_due':
      case 'feed_overdue':
        appRouter.go('/feeding');
      case 'sleep_due':
      case 'sleep_overdue':
        appRouter.go('/sleep');
      default:
        appRouter.go('/dashboard');
    }
  }

  /// Fire the parent "report submitted" push. Safe to call after a submit;
  /// failures never surface to the user.
  static Future<void> notifyReportSubmitted({
    required String babyId,
    String? babyName,
    String? actorName,
  }) async {
    try {
      await SupabaseService.client.functions.invoke(
        'notify-report-submitted',
        body: {
          'baby_id': babyId,
          'baby_name': babyName,
          'actor_name': actorName,
        },
      );
    } catch (e) {
      debugPrint('notifyReportSubmitted failed: $e');
    }
  }
}
