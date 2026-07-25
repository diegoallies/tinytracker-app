import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'supabase_service.dart';

/// Native APNs remote-push (no Firebase).
///
/// The iOS side (AppDelegate) registers for remote notifications and hands the
/// device token back over the `tinytrack/push` MethodChannel. We upsert it into
/// `device_tokens` so the `notify-report-submitted` edge function can reach the
/// parents' phones.
///
/// Everything is guarded: if push isn't configured yet (no APNs key / capability)
/// the app keeps working, the notification simply doesn't fire.
class PushService {
  static const _channel = MethodChannel('tinytrack/push');

  /// Call once after Supabase is initialised (main.dart) and again after login.
  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToken' && call.arguments is String) {
        await _storeToken(call.arguments as String);
      }
    });
    try {
      // Ask iOS to register for remote notifications; the token comes back via
      // the onToken handler above.
      await _channel.invokeMethod('registerForRemoteNotifications');
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  static Future<void> _storeToken(String token) async {
    final userId = SupabaseService.userId;
    if (userId == null || token.isEmpty) return;
    try {
      await SupabaseService.client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': 'ios',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');
    } catch (e) {
      debugPrint('push token upsert failed: $e');
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
