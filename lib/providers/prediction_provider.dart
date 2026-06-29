import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prediction_service.dart';
import '../services/feeding_guidelines.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';
import 'sleep_provider.dart';
import '../utils/date_utils.dart';

/// Look-back window for pattern detection.
const _patternWindow = Duration(days: 7);

/// Predicted next feeding, from the last week of feeding times.
/// Null when there isn't enough history to predict confidently.
final nextFeedingPredictionProvider =
    FutureProvider<NextEventPrediction?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  try {
    final now = DateTime.now();
    final since = now.subtract(_patternWindow);
    final data = await SupabaseService.client
        .from('feedings')
        .select('logged_at, amount_ml')
        .eq('baby_id', baby.id)
        .isFilter('deleted_at', null)
        .gte('logged_at', since.toUtc().toIso8601String())
        // Descending so the limit drops the OLDEST events when over the cap.
        .order('logged_at', ascending: false)
        .limit(120);

    final times = data
        .map((row) => parseDbTime(row['logged_at'] as String).toLocal())
        .toList();
    final pattern = PredictionService.predictNextFromEvents(times, now: now);

    // Age-based + amount-scaled timing (preferred for bottle feeds):
    // a full feed -> full interval, a small feed -> due proportionally sooner.
    // data is newest-first, so the first row is the most recent feed.
    if (data.isNotEmpty) {
      final lastAmount = data.first['amount_ml'] as int?;
      final lastTime = parseDbTime(data.first['logged_at'] as String).toLocal();
      if (lastAmount != null && lastAmount > 0) {
        final target = FeedingGuidelines.targetForAgeDays(baby.ageDays);
        final intervalHrs = FeedingGuidelines.nextIntervalHours(lastAmount, target);
        final gap = Duration(minutes: (intervalHrs * 60).round());
        return NextEventPrediction(
          expectedAt: lastTime.add(gap),
          typicalGap: gap,
          sampleSize: pattern?.sampleSize ?? 0,
          // Strong confidence when the amount is known; blend with pattern if present.
          confidence: pattern?.confidence ?? 0.6,
        );
      }
    }

    // Breast / no recorded volume -> fall back to the learned pattern.
    return pattern;
  } catch (e, st) {
    debugPrint('nextFeedingPredictionProvider error: $e\n$st');
    return null; // Prediction is a bonus - never break the screen for it.
  }
});

/// Predicted next nap, from awake windows in the last week of sleep.
/// Null while the baby is currently asleep or history is too thin.
final nextNapPredictionProvider =
    FutureProvider<NextEventPrediction?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  // No nap prediction needed while a sleep session is running.
  final active = await ref.watch(activeSleepProvider.future);
  if (active != null) return null;

  try {
    final since = DateTime.now().subtract(_patternWindow);
    final data = await SupabaseService.client
        .from('sleeps')
        .select('start_time, end_time')
        .eq('baby_id', baby.id)
        .not('end_time', 'is', null)
        .isFilter('deleted_at', null)
        .gte('start_time', since.toUtc().toIso8601String())
        // Descending so the limit drops the OLDEST sessions when over the cap.
        .order('start_time', ascending: false)
        .limit(80);

    final sessions = data
        .map((row) => (
              start: parseDbTime(row['start_time'] as String).toLocal(),
              end: parseDbTime(row['end_time'] as String).toLocal(),
            ))
        .toList();
    return PredictionService.predictNextNap(sessions, now: DateTime.now());
  } catch (e, st) {
    debugPrint('nextNapPredictionProvider error: $e\n$st');
    return null;
  }
});
