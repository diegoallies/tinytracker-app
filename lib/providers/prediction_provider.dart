import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prediction_service.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';
import 'sleep_provider.dart';

/// Look-back window for pattern detection.
const _patternWindow = Duration(days: 7);

/// Predicted next feeding, from the last week of feeding times.
/// Null when there isn't enough history to predict confidently.
final nextFeedingPredictionProvider =
    FutureProvider<NextEventPrediction?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  try {
    final since = DateTime.now().subtract(_patternWindow);
    final data = await SupabaseService.client
        .from('feedings')
        .select('logged_at')
        .eq('baby_id', baby.id)
        .gte('logged_at', since.toUtc().toIso8601String())
        // Descending so the limit drops the OLDEST events when over the cap.
        .order('logged_at', ascending: false)
        .limit(120);

    final times = data
        .map((row) => DateTime.parse(row['logged_at'] as String).toLocal())
        .toList();
    return PredictionService.predictNextFromEvents(times);
  } catch (e, st) {
    debugPrint('nextFeedingPredictionProvider error: $e\n$st');
    return null; // Prediction is a bonus — never break the screen for it.
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
        .gte('start_time', since.toUtc().toIso8601String())
        // Descending so the limit drops the OLDEST sessions when over the cap.
        .order('start_time', ascending: false)
        .limit(80);

    final sessions = data
        .map((row) => (
              start: DateTime.parse(row['start_time'] as String).toLocal(),
              end: DateTime.parse(row['end_time'] as String).toLocal(),
            ))
        .toList();
    return PredictionService.predictNextNap(sessions);
  } catch (e, st) {
    debugPrint('nextNapPredictionProvider error: $e\n$st');
    return null;
  }
});
