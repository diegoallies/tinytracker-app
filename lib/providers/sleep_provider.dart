import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_session.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final activeSleepProvider = FutureProvider<SleepSession?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  final data = await SupabaseService.client
      .from('sleeps')
      .select()
      .eq('baby_id', baby.id)
      .isFilter('end_time', null)
      .isFilter('deleted_at', null)
      .order('start_time', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return SleepSession.fromJson(data);
});

final recentSleepsProvider = FutureProvider<List<SleepSession>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('sleeps')
      .select('*')
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .isFilter('deleted_at', null)
      .order('start_time', ascending: false)
      .limit(10);

  return data.map<SleepSession>((json) => SleepSession.fromJson(json)).toList();
});

final todaySleepMinutesProvider = FutureProvider<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('sleeps')
      .select('duration_minutes')
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .isFilter('deleted_at', null)
      .gte('start_time', AppDateUtils.todayStart.toUtc().toIso8601String());

  int total = 0;
  for (final s in data) {
    total += (s['duration_minutes'] as int?) ?? 0;
  }
  return total;
});

class SleepActions {
  static Future<SleepSession?> startSleep(
    String babyId, {
    // Watch taps arrive here via WatchBridge; the phone UI leaves the default.
    String source = AnalyticsService.sourcePhone,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final data = await SupabaseService.client.from('sleeps').insert({
      'baby_id': babyId,
      'user_id': userId,
      'start_time': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    // Baby is now asleep - clear any pending "nap due / overdue" reminders.
    try {
      await NotificationService.cancelSleepReminders();
    } catch (e) {
      debugPrint('sleep reminder cancel failed: $e');
    }

    // Logged on start, not stop: it's the deliberate user action, and counting
    // it here can't double up with stopSleep.
    AnalyticsService.logSleep(source: source);

    return SleepSession.fromJson(data);
  }

  static Future<void> stopSleep(String sleepId, DateTime startTime) async {
    final now = DateTime.now();
    final duration = now.difference(startTime).inMinutes;

    await SupabaseService.client.from('sleeps').update({
      'end_time': now.toUtc().toIso8601String(),
      'duration_minutes': duration,
    }).eq('id', sleepId);

    // Baby just woke - schedule the next "nap due / overdue" reminders off the
    // wake window. A save must never fail because of a reminder.
    try {
      final window = await NotificationService.getSleepWindow();
      await NotificationService.scheduleSleepReminder(
        lastWakeTime: now,
        wakeWindowMinutes: window,
      );
    } catch (e) {
      debugPrint('sleep reminder scheduling failed: $e');
    }
  }

  static Future<void> deleteSleep(String sleepId) async {
    await SupabaseService.client
        .from('sleeps')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', sleepId);
  }

  /// Start an active session with an explicit (backdated) start time.
  /// Use when the baby has been sleeping for a while and the user is logging it late.
  static Future<SleepSession?> startSleepAt({
    required String babyId,
    required DateTime start,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    if (start.isAfter(DateTime.now())) {
      throw ArgumentError('Start time cannot be in the future');
    }

    final data = await SupabaseService.client.from('sleeps').insert({
      'baby_id': babyId,
      'user_id': userId,
      'start_time': start.toUtc().toIso8601String(),
    }).select().single();

    try {
      await NotificationService.cancelSleepReminders();
    } catch (e) {
      debugPrint('sleep reminder cancel failed: $e');
    }

    return SleepSession.fromJson(data);
  }

  /// Insert a completed session with explicit start/end times (for backdating).
  static Future<SleepSession?> logBackdated({
    required String babyId,
    required DateTime start,
    required DateTime end,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final duration = end.difference(start).inMinutes;
    if (duration <= 0) {
      throw ArgumentError('End time must be after start time');
    }
    if (end.isAfter(DateTime.now())) {
      throw ArgumentError('End time cannot be in the future');
    }

    final data = await SupabaseService.client.from('sleeps').insert({
      'baby_id': babyId,
      'user_id': userId,
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'duration_minutes': duration,
    }).select().single();

    return SleepSession.fromJson(data);
  }
}
