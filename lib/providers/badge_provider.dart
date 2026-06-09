import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pattern_badge.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final earnedBadgesProvider = FutureProvider.autoDispose<List<PatternBadge>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final evaluator = BadgeEvaluator(babyId: baby.id);
  return evaluator.evaluate();
});

final newBadgesProvider = FutureProvider.autoDispose<List<PatternBadge>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final earned = await ref.watch(earnedBadgesProvider.future);
  final earnedIds = earned.where((b) => b.isEarned).map((b) => b.id).toSet();

  final prefs = await SharedPreferences.getInstance();
  final seenJson = prefs.getString('seen_badges_${baby.id}') ?? '[]';
  final seenIds = Set<String>.from(jsonDecode(seenJson) as List);

  final newBadges = earned.where((b) => b.isEarned && !seenIds.contains(b.id)).toList();

  // Mark as seen
  if (newBadges.isNotEmpty) {
    seenIds.addAll(earnedIds);
    await prefs.setString('seen_badges_${baby.id}', jsonEncode(seenIds.toList()));
  }

  return newBadges;
});

class BadgeEvaluator {
  final String babyId;

  BadgeEvaluator({required this.babyId});

  Future<List<PatternBadge>> evaluate() async {
    final client = SupabaseService.client;
    final fourteenDaysAgo = AppDateUtils.daysAgoStart(14).toUtc().toIso8601String();

    final results = await Future.wait([
      // Feedings last 14 days
      client.from('feedings').select('logged_at').eq('baby_id', babyId)
          .gte('logged_at', fourteenDaysAgo),
      // Sleeps last 14 days
      client.from('sleeps').select('start_time, duration_minutes').eq('baby_id', babyId)
          .not('end_time', 'is', null)
          .gte('start_time', fourteenDaysAgo),
      // Total feeds ever
      client.from('feedings').select('id').eq('baby_id', babyId),
      // Total diapers ever
      client.from('diapers').select('id').eq('baby_id', babyId),
      // First activity date (oldest feed)
      client.from('feedings').select('logged_at').eq('baby_id', babyId)
          .order('logged_at', ascending: true).limit(1),
    ]);

    final recentFeedings = results[0] as List;
    final recentSleeps = results[1] as List;
    final totalFeeds = (results[2] as List).length;
    final totalDiapers = (results[3] as List).length;
    final firstFeed = results[4] as List;

    final now = DateTime.now();
    final earnedMap = <String, bool>{};

    // Sleep streaks: count consecutive days with 8+ hours
    final sleepByDay = <String, int>{};
    for (final s in recentSleeps) {
      final dt = DateTime.parse(s['start_time']);
      final key = '${dt.year}-${dt.month}-${dt.day}';
      sleepByDay[key] = (sleepByDay[key] ?? 0) + ((s['duration_minutes'] as int?) ?? 0);
    }
    final sleepStreak = _consecutiveDaysWithMinSleep(sleepByDay, 480);
    earnedMap['sleep_streak_3'] = sleepStreak >= 3;
    earnedMap['sleep_streak_5'] = sleepStreak >= 5;
    earnedMap['sleep_streak_7'] = sleepStreak >= 7;
    earnedMap['sleep_streak_14'] = sleepStreak >= 14;

    // Feeding consistency: 6+ feeds/day for 3 consecutive days
    final feedsByDay = <String, int>{};
    for (final f in recentFeedings) {
      final dt = DateTime.parse(f['logged_at']);
      final key = '${dt.year}-${dt.month}-${dt.day}';
      feedsByDay[key] = (feedsByDay[key] ?? 0) + 1;
    }
    final feedStreak = _consecutiveDaysWithMinFeeds(feedsByDay, 6);
    earnedMap['consistent_feeder_3'] = feedStreak >= 3;

    // Total counts
    earnedMap['feeding_100'] = totalFeeds >= 100;
    earnedMap['feeding_500'] = totalFeeds >= 500;
    earnedMap['diaper_100'] = totalDiapers >= 100;
    earnedMap['diaper_500'] = totalDiapers >= 500;

    // Days tracking
    if (firstFeed.isNotEmpty) {
      final firstDate = DateTime.parse(firstFeed[0]['logged_at']);
      final daysTracking = now.difference(firstDate).inDays;
      earnedMap['first_week'] = daysTracking >= 7;
      earnedMap['thirty_days'] = daysTracking >= 30;
    }

    // Night owl / early bird
    for (final f in recentFeedings) {
      final dt = DateTime.parse(f['logged_at']);
      if (dt.hour >= 0 && dt.hour < 3) earnedMap['night_owl'] = true;
      if (dt.hour >= 3 && dt.hour < 5) earnedMap['early_bird'] = true;
    }

    return PatternBadge.allBadges.map((badge) {
      final earned = earnedMap[badge.id] ?? false;
      return badge.copyWith(
        isEarned: earned,
        earnedAt: earned ? now : null,
      );
    }).toList();
  }

  int _consecutiveDaysWithMinSleep(Map<String, int> sleepByDay, int minMinutes) {
    int maxStreak = 0;
    int currentStreak = 0;

    for (int i = 13; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      final mins = sleepByDay[key] ?? 0;

      if (mins >= minMinutes) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }
    return maxStreak;
  }

  int _consecutiveDaysWithMinFeeds(Map<String, int> feedsByDay, int minFeeds) {
    int maxStreak = 0;
    int currentStreak = 0;

    for (int i = 13; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      final count = feedsByDay[key] ?? 0;

      if (count >= minFeeds) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }
    return maxStreak;
  }
}
