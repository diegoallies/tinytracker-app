import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_service.dart';
import '../providers/baby_provider.dart';
import '../providers/feeding_provider.dart';
import '../providers/diaper_provider.dart';
import '../providers/sleep_provider.dart';
import '../providers/health_provider.dart';
import '../providers/prediction_provider.dart';
import '../providers/baby_medication_provider.dart';
import '../utils/date_utils.dart';

/// Bridges the Apple Watch companion app (native SwiftUI) and this Flutter app.
///
/// The watch never touches Supabase directly. It sends one-tap log events over
/// WatchConnectivity to the iOS host, which forwards them here via the
/// `tinytrack/watch` MethodChannel. We write them through the SAME action
/// classes the phone UI uses (so offline-queueing, validation etc. all apply),
/// then push a fresh summary (next feed, today's totals, scheduled meds) back
/// to the watch for its home screen + complication.
class WatchBridge {
  WatchBridge._();
  static final WatchBridge instance = WatchBridge._();

  static const MethodChannel _channel = MethodChannel('tinytrack/watch');
  ProviderContainer? _container;

  /// Wire up the channel. Call once from main() with the app's container.
  void init(ProviderContainer container) {
    _container = container;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onWatchEvent') return null;
    final container = _container;
    if (container == null) return null;

    final args = (call.arguments as Map).cast<String, dynamic>();
    final action = args['action'] as String?;
    final baby = container.read(selectedBabyProvider);
    if (action == null || baby == null) return false;

    final loggedAt = args['loggedAt'] is String
        ? DateTime.tryParse(args['loggedAt'] as String)?.toLocal()
        : null;

    try {
      switch (action) {
        case 'logFeed':
          await FeedingActions.logFeeding(
            babyId: baby.id,
            type: (args['type'] as String?) ?? 'bottle',
            amountMl: (args['amountMl'] as num?)?.toInt(),
            loggedAt: loggedAt,
          );
          break;
        case 'logDiaper':
          await DiaperActions.logDiaper(
            babyId: baby.id,
            type: (args['type'] as String?) ?? 'wet',
            loggedAt: loggedAt,
          );
          break;
        case 'sleepStart':
          await SleepActions.startSleep(baby.id);
          break;
        case 'sleepStop':
          final active = await container.read(activeSleepProvider.future);
          if (active != null) {
            await SleepActions.stopSleep(active.id, active.startTime);
          }
          break;
        case 'logMed':
          await HealthActions.logHealth(
            babyId: baby.id,
            medication: args['name'] as String?,
            loggedAt: loggedAt,
          );
          break;
        default:
          debugPrint('WatchBridge: unknown action "$action"');
      }
    } catch (e, st) {
      debugPrint('WatchBridge action "$action" failed: $e\n$st');
    }

    // Refresh the watch with the new state regardless of success.
    await pushSummary();
    return true;
  }

  /// Compute the current at-a-glance summary and push it to the watch.
  /// Safe to call any time (app start, after a log, on data change).
  Future<void> pushSummary() async {
    final container = _container;
    if (container == null) return;
    final baby = container.read(selectedBabyProvider);
    if (baby == null) return;

    try {
      final client = SupabaseService.client;
      final now = DateTime.now();
      final todayStart = AppDateUtils.todayStart.toUtc().toIso8601String();

      final feeds = await client
          .from('feedings')
          .select('amount_ml')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', todayStart);
      var totalMl = 0;
      for (final f in feeds) {
        totalMl += (f['amount_ml'] as int?) ?? 0;
      }

      final sleeps = await client
          .from('sleeps')
          .select('duration_minutes')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .not('end_time', 'is', null)
          .gte('start_time', todayStart);
      var sleepMinutes = 0;
      for (final s in sleeps) {
        sleepMinutes += (s['duration_minutes'] as int?) ?? 0;
      }

      final diapers = await client
          .from('diapers')
          .select('id')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', todayStart);

      final prediction =
          await container.read(nextFeedingPredictionProvider.future);
      final meds = await container.read(babyMedicationsProvider.future);
      final scheduledMeds = [
        for (final m in meds)
          if (!m.asNeeded) m.name,
      ];

      // Live sleep state so the watch mirrors the phone (source of truth):
      // if a session is running, the watch shows the carried-over timer and
      // can only Stop, not Start a second one.
      final activeSleep = await container.read(activeSleepProvider.future);

      // ── Feats 1 & 2: last 7 days of daily summaries (home left-scroll) +
      //    recent per-type record logs (per-page left-scroll). One windowed
      //    query per type, then derive both views from it.
      final weekStartIso = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6))
          .toUtc()
          .toIso8601String();

      final feedRows = await client
          .from('feedings')
          .select('id, type, amount_ml, logged_at')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', weekStartIso)
          .order('logged_at', ascending: false);
      final diaperRows = await client
          .from('diapers')
          .select('id, type, logged_at')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', weekStartIso)
          .order('logged_at', ascending: false);
      final sleepRows = await client
          .from('sleeps')
          .select('id, start_time, end_time, duration_minutes')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .not('end_time', 'is', null)
          .gte('start_time', weekStartIso)
          .order('start_time', ascending: false);

      String dayKeyOf(String iso) {
        final l = DateTime.parse(iso).toLocal();
        return '${l.year.toString().padLeft(4, '0')}-'
            '${l.month.toString().padLeft(2, '0')}-'
            '${l.day.toString().padLeft(2, '0')}';
      }

      // 7 day buckets, today first.
      final buckets = <String, Map<String, int>>{};
      for (var i = 0; i < 7; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i));
        final key = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        buckets[key] = {'feeds': 0, 'totalMl': 0, 'sleepMinutes': 0, 'diapers': 0};
      }
      for (final f in feedRows) {
        final b = buckets[dayKeyOf(f['logged_at'] as String)];
        if (b != null) {
          b['feeds'] = b['feeds']! + 1;
          b['totalMl'] = b['totalMl']! + ((f['amount_ml'] as int?) ?? 0);
        }
      }
      for (final d in diaperRows) {
        final b = buckets[dayKeyOf(d['logged_at'] as String)];
        if (b != null) b['diapers'] = b['diapers']! + 1;
      }
      for (final s in sleepRows) {
        final b = buckets[dayKeyOf(s['start_time'] as String)];
        if (b != null) b['sleepMinutes'] = b['sleepMinutes']! + ((s['duration_minutes'] as int?) ?? 0);
      }
      final dailySummaries = [
        for (final e in buckets.entries)
          {
            'date': e.key,
            'feeds': e.value['feeds'],
            'totalMl': e.value['totalMl'],
            'sleepMinutes': e.value['sleepMinutes'],
            'diapers': e.value['diapers'],
          }
      ];

      String iso(String s) => DateTime.parse(s).toUtc().toIso8601String();
      final feedLog = [
        for (final f in feedRows.take(25))
          {'id': f['id'], 'type': f['type'], 'amountMl': f['amount_ml'], 'loggedAt': iso(f['logged_at'] as String)}
      ];
      final diaperLog = [
        for (final d in diaperRows.take(25))
          {'id': d['id'], 'type': d['type'], 'loggedAt': iso(d['logged_at'] as String)}
      ];
      final sleepLog = [
        for (final s in sleepRows.take(25))
          {
            'id': s['id'],
            'durationMinutes': s['duration_minutes'],
            'startedAt': iso(s['start_time'] as String),
            'endedAt': s['end_time'] != null ? iso(s['end_time'] as String) : null,
          }
      ];

      await _channel.invokeMethod('updateWatchContext', <String, dynamic>{
        'nextFeedAt': prediction?.expectedAt.toUtc().toIso8601String(),
        'feedsToday': feeds.length,
        'totalMlToday': totalMl,
        'sleepMinutesToday': sleepMinutes,
        'diapersToday': diapers.length,
        'scheduledMeds': scheduledMeds,
        // Bug 1: baby identity for the watch avatar.
        'babyName': baby.name,
        'babyPhotoUrl': baby.photoUrl,
        // Bug 2: ongoing sleep (null when awake) so the watch carries the timer.
        'sleepStartedAt': activeSleep?.startTime.toUtc().toIso8601String(),
        'isSleeping': activeSleep != null,
        // Feat 1: previous days. Feat 2: per-type record logs.
        'dailySummaries': dailySummaries,
        'feedLog': feedLog,
        'diaperLog': diaperLog,
        'sleepLog': sleepLog,
      });
    } catch (e, st) {
      debugPrint('WatchBridge pushSummary failed: $e\n$st');
    }
  }
}
