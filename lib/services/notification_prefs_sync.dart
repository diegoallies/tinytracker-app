import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Mirrors the notification settings into `notification_prefs` on the server.
///
/// Feed and sleep reminders are now sent by the `check-overdue` cron function
/// rather than scheduled on-device, which means the server has to know each
/// user's thresholds — a cron job can't read a phone's SharedPreferences.
///
/// SharedPreferences stays as the local cache so the settings UI is instant and
/// works offline; this class keeps the two in step. Every call is guarded:
/// failing to sync must never break the settings screen.
class NotificationPrefsSync {
  static const _keys = {
    'feeding_enabled': 'feeding_reminder_enabled',
    'feeding_interval_minutes': 'feeding_reminder_interval',
    'sleep_enabled': 'sleep_reminder_enabled',
    'sleep_window_minutes': 'sleep_reminder_window',
    'medication_enabled': 'medication_reminder_enabled',
    'weekly_report_enabled': 'weekly_report_reminder_enabled',
  };

  /// Reconcile local and server prefs once per launch.
  ///
  /// If the server has no row yet this is an upgrading user, so their existing
  /// local settings are pushed up — nobody silently loses a tuned interval.
  /// Otherwise the server wins, so a second device picks up changes made on the
  /// first.
  static Future<void> reconcile() async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    try {
      final existing = await SupabaseService.client
          .from('notification_prefs')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (existing == null) {
        await push();
      } else {
        await _pullInto(existing);
      }
    } catch (e) {
      debugPrint('notification prefs reconcile failed: $e');
    }
  }

  /// Write the current local settings up to the server. Call after any change.
  static Future<void> push() async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await SupabaseService.client.from('notification_prefs').upsert({
        'user_id': userId,
        'feeding_enabled':
            prefs.getBool('feeding_reminder_enabled') ?? false,
        'feeding_interval_minutes':
            prefs.getInt('feeding_reminder_interval') ?? 180,
        'sleep_enabled': prefs.getBool('sleep_reminder_enabled') ?? false,
        'sleep_window_minutes': prefs.getInt('sleep_reminder_window') ?? 120,
        'medication_enabled':
            prefs.getBool('medication_reminder_enabled') ?? false,
        'weekly_report_enabled':
            prefs.getBool('weekly_report_reminder_enabled') ?? false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('notification prefs push failed: $e');
    }
  }

  static Future<void> _pullInto(Map<String, dynamic> row) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _keys.entries) {
      final value = row[entry.key];
      if (value is bool) {
        await prefs.setBool(entry.value, value);
      } else if (value is int) {
        await prefs.setInt(entry.value, value);
      }
    }
  }
}
