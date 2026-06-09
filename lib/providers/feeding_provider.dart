import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/feeding.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final recentFeedingsProvider = FutureProvider<List<Feeding>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('feedings')
        .select('*')
        .eq('baby_id', baby.id)
        .order('logged_at', ascending: false)
        .limit(10);

    return data.map<Feeding>((json) => Feeding.fromJson(json)).toList();
  } catch (e, st) {
    debugPrint('recentFeedingsProvider error: $e\n$st');
    rethrow;
  }
});

/// A feeding paired with the medication entry (if any) that was logged at
/// the same time. Feeding + meds are inserted with the identical `logged_at`,
/// so we join in-Dart with a 1-second tolerance to absorb any DB round-trip
/// precision loss.
class FeedingWithMed {
  final Feeding feeding;
  final String? medication;
  final String? dosage;

  const FeedingWithMed({
    required this.feeding,
    this.medication,
    this.dosage,
  });

  bool get hasMed => medication != null && medication!.isNotEmpty;
}

final recentFeedingsWithMedsProvider =
    FutureProvider<List<FeedingWithMed>>((ref) async {
  final feedings = await ref.watch(recentFeedingsProvider.future);
  if (feedings.isEmpty) return const [];

  final baby = ref.read(selectedBabyProvider);
  if (baby == null) {
    return feedings.map((f) => FeedingWithMed(feeding: f)).toList();
  }

  // Fetch meds in a time window covering all recent feedings.
  final times = [for (final f in feedings) f.loggedAt]..sort();
  final earliest = times.first.subtract(const Duration(seconds: 2));
  final latest = times.last.add(const Duration(seconds: 2));

  try {
    final medsData = await SupabaseService.client
        .from('health_logs')
        .select('logged_at, medication, dosage')
        .eq('baby_id', baby.id)
        .not('medication', 'is', null)
        .gte('logged_at', earliest.toUtc().toIso8601String())
        .lte('logged_at', latest.toUtc().toIso8601String());

    final meds = medsData
        .map((m) => (
              loggedAt: DateTime.parse(m['logged_at'] as String),
              medication: m['medication'] as String?,
              dosage: m['dosage'] as String?,
            ))
        .toList();

    return feedings.map((f) {
      for (final m in meds) {
        if ((m.loggedAt.difference(f.loggedAt)).abs() <
            const Duration(seconds: 1)) {
          return FeedingWithMed(
            feeding: f,
            medication: m.medication,
            dosage: m.dosage,
          );
        }
      }
      return FeedingWithMed(feeding: f);
    }).toList();
  } catch (e, st) {
    debugPrint('recentFeedingsWithMedsProvider error: $e\n$st');
    // Fall back to feedings without meds info rather than failing the screen.
    return feedings.map((f) => FeedingWithMed(feeding: f)).toList();
  }
});

final todayFeedCountProvider = FutureProvider<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('feedings')
      .select('id')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toUtc().toIso8601String());

  return data.length;
});

class FeedingActions {
  static Future<void> logFeeding({
    required String babyId,
    required String type,
    int? durationMinutes,
    int? amountMl,
    int? quality,
    bool hadSpitup = false,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    final ts = loggedAt ?? DateTime.now();
    final payload = {
      'baby_id': babyId,
      'user_id': userId,
      'type': type,
      'duration_minutes': durationMinutes,
      'amount_ml': amountMl,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': ts.toUtc().toIso8601String(),
    };

    // quality/had_spitup land with the Care Pack migration; retry without
    // them if the columns don't exist yet so logging never breaks.
    var inserted = false;
    if (quality != null || hadSpitup) {
      try {
        await SupabaseService.client.from('feedings').insert({
          ...payload,
          'quality': ?quality,
          'had_spitup': hadSpitup,
        });
        inserted = true;
      } on PostgrestException catch (e) {
        debugPrint('feeding insert with care-pack fields failed (${e.code}), retrying without');
      }
    }
    if (!inserted) {
      await SupabaseService.client.from('feedings').insert(payload);
    }

    // Reschedule feeding reminder from the actual logged time
    final interval = await NotificationService.getReminderInterval();
    await NotificationService.scheduleFeedingReminder(
      lastFeedTime: ts,
      intervalMinutes: interval,
    );
  }

  static Future<void> deleteFeeding(String feedingId) async {
    await SupabaseService.client
        .from('feedings')
        .delete()
        .eq('id', feedingId);
  }
}
