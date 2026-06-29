import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/feeding_guidelines.dart';
import 'feeding_provider.dart';
import 'baby_provider.dart';
import 'baby_medication_provider.dart';

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
  final configuredInterval = ref.watch(feedingReminderIntervalProvider);
  final baby = ref.watch(selectedBabyProvider);

  if (!enabled || baby == null) return;

  final feedingsAsync = ref.watch(recentFeedingsProvider);
  feedingsAsync.whenData((feedings) {
    if (feedings.isEmpty) return;
    final last = feedings.first;

    // Smart timing: scale the reminder by how much the baby actually drank,
    // against the age-based target. A full feed -> full interval; a small feed
    // -> due sooner. Breast / no recorded volume -> the configured interval.
    var intervalMinutes = configuredInterval;
    final amt = last.amountMl;
    if (amt != null && amt > 0) {
      final target = FeedingGuidelines.targetForAgeDays(baby.ageDays);
      intervalMinutes =
          (FeedingGuidelines.nextIntervalHours(amt, target) * 60).round();
    }

    NotificationService.scheduleFeedingReminder(
      lastFeedTime: last.loggedAt,
      intervalMinutes: intervalMinutes,
    );
  });
});

// ── Medication reminders ────────────────────────────────────────────────

final medicationReminderEnabledProvider =
    StateNotifierProvider<MedicationReminderEnabledNotifier, bool>((ref) {
  return MedicationReminderEnabledNotifier();
});

class MedicationReminderEnabledNotifier extends StateNotifier<bool> {
  MedicationReminderEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    state = await NotificationService.isMedicationReminderEnabled();
  }

  Future<void> toggle() async {
    state = !state;
    await NotificationService.setMedicationReminderEnabled(state);
    if (state) await NotificationService.requestPermissions();
  }
}

/// Schedules "medicine due" reminders for scheduled meds. For each scheduled
/// (non as-needed) med it computes the next due time from the last dose +
/// the med's min interval (or 24h / frequency-per-day), and schedules a local
/// notification. As-needed meds are skipped.
final medicationReminderSchedulerProvider = Provider<void>((ref) {
  final enabled = ref.watch(medicationReminderEnabledProvider);
  final baby = ref.watch(selectedBabyProvider);
  if (!enabled || baby == null) return;

  final medsAsync = ref.watch(babyMedicationsProvider);
  final dosesAsync = ref.watch(medicationDosesTodayProvider);

  final meds = medsAsync.asData?.value;
  final doses = dosesAsync.asData?.value;
  if (meds == null || doses == null) return;

  final due = <({String name, DateTime dueAt})>[];
  for (final med in meds) {
    if (med.asNeeded) continue;
    // Determine the interval between doses for this med.
    double? intervalHours = med.minIntervalHours;
    if (intervalHours == null &&
        med.frequencyPerDay != null &&
        med.frequencyPerDay! > 0) {
      intervalHours = 24 / med.frequencyPerDay!;
    }
    if (intervalHours == null || intervalHours <= 0) continue;

    final today = doses[med.name.trim().toLowerCase()];
    if (today == null || today.isEmpty) continue; // no dose yet -> nothing to time from
    final lastDose = today.first; // newest first
    due.add((
      name: med.name,
      dueAt: lastDose.add(Duration(minutes: (intervalHours * 60).round())),
    ));
  }

  NotificationService.scheduleMedicationReminders(due);
});
