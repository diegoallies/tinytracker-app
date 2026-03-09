import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'feeding_provider.dart';
import 'baby_provider.dart';

final feedingReminderEnabledProvider = StateNotifierProvider<FeedingReminderEnabledNotifier, bool>((ref) {
  return FeedingReminderEnabledNotifier();
});

class FeedingReminderEnabledNotifier extends StateNotifier<bool> {
  FeedingReminderEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('feeding_reminder_enabled') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    await NotificationService.setReminderEnabled(state);
    if (state) {
      await NotificationService.requestPermissions();
    }
  }
}

final feedingReminderIntervalProvider = StateNotifierProvider<FeedingReminderIntervalNotifier, int>((ref) {
  return FeedingReminderIntervalNotifier();
});

class FeedingReminderIntervalNotifier extends StateNotifier<int> {
  FeedingReminderIntervalNotifier() : super(180) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('feeding_reminder_interval') ?? 180;
  }

  Future<void> setInterval(int minutes) async {
    state = minutes;
    await NotificationService.setReminderInterval(minutes);
  }
}

final feedingReminderSchedulerProvider = Provider<void>((ref) {
  final enabled = ref.watch(feedingReminderEnabledProvider);
  final interval = ref.watch(feedingReminderIntervalProvider);
  final baby = ref.watch(selectedBabyProvider);

  if (!enabled || baby == null) return;

  final feedingsAsync = ref.watch(recentFeedingsProvider);
  feedingsAsync.whenData((feedings) {
    if (feedings.isNotEmpty) {
      NotificationService.scheduleFeedingReminder(
        lastFeedTime: feedings.first.loggedAt,
        intervalMinutes: interval,
      );
    }
  });
});
