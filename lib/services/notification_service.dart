import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_prefs_sync.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _feedingChannelId = 'feeding_reminders';
  static const _feedingNotificationId = 1001;
  static const _feedingOverdueChannelId = 'feeding_overdue';
  static const _feedingOverdueNotificationId = 1003;
  static const _sleepChannelId = 'sleep_reminders';
  static const _sleepNotificationId = 1004;
  static const _sleepOverdueChannelId = 'sleep_overdue';
  static const _sleepOverdueNotificationId = 1005;
  // How long after a "due" reminder we escalate to "overdue".
  static const _overdueGraceMinutes = 45;
  static const _weeklyReportChannelId = 'weekly_report_reminders';
  static const _weeklyReportNotificationId = 1002;
  static const _medicationChannelId = 'medication_reminders';
  // Foreground FCM pushes (see showRemoteNotification). Distinct channel so
  // users can mute family updates without losing their own reminders.
  static const _remoteChannelId = 'remote_updates';
  static const _remoteNotificationId = 1200;
  // Medication reminders use a reserved id block: _medicationIdBase .. +maxMeds.
  static const _medicationIdBase = 1100;
  static const _maxMedReminders = 30;

  static Future<void> initialize() async {
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);

    // Background/killed FCM pushes are drawn by the OS, not by Dart, using the
    // channel named in AndroidManifest.xml. On Android 8+ a notification
    // pointing at a channel that doesn't exist yet is dropped silently, so it
    // has to be created up front rather than lazily on first show().
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _remoteChannelId,
            'Updates from your family',
            description:
                'Alerts when someone sharing your baby logs or submits something.',
            importance: Importance.high,
          ),
        );
  }

  /// Renders an FCM push that arrived while the app was in the foreground.
  ///
  /// Android draws nothing for foreground messages, so `PushService` routes
  /// them here. iOS presents them itself via
  /// `setForegroundNotificationPresentationOptions` and never calls this.
  static Future<void> showRemoteNotification({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _remoteChannelId,
        'Updates from your family',
        channelDescription:
            'Alerts when someone sharing your baby logs or submits something.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(_remoteNotificationId, title, body, details);
  }

  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Schedules the next feeding reminder with the OS (survives the app being
  /// backgrounded or killed - the old Future.delayed approach did not).
  static Future<void> scheduleFeedingReminder({
    required DateTime lastFeedTime,
    int intervalMinutes = 180,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('feeding_reminder_enabled') ?? false;
    if (!enabled) return;

    // Replace any previously scheduled reminders (due + overdue).
    await _plugin.cancel(_feedingNotificationId);
    await _plugin.cancel(_feedingOverdueNotificationId);

    final triggerTime = lastFeedTime.add(Duration(minutes: intervalMinutes));
    final delay = triggerTime.difference(DateTime.now());
    if (delay.isNegative) return;

    // Anchoring to tz now + delay sidesteps needing the device's named
    // timezone - the instant is correct even if tz.local is UTC.
    final scheduledAt = tz.TZDateTime.now(tz.local).add(delay);

    final hours = intervalMinutes ~/ 60;
    final mins = intervalMinutes % 60;
    final timeStr = hours > 0
        ? (mins > 0 ? '$hours hr ${mins}min' : '$hours hours')
        : '$mins minutes';

    const androidDetails = AndroidNotificationDetails(
      _feedingChannelId,
      'Feeding Reminders',
      channelDescription: 'Reminders when it\'s time to feed',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _feedingNotificationId,
      'Time to feed',
      'It\'s been $timeStr since the last feed.',
      scheduledAt,
      details,
      // Inexact keeps us clear of the Android 12+ exact-alarm permission;
      // a feeding nudge can be a couple of minutes off.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    // Escalation: if no feed is logged, a second "overdue" reminder fires
    // _overdueGraceMinutes after the due one. Logging a feed reschedules both.
    final overdueDelay = delay + const Duration(minutes: _overdueGraceMinutes);
    final overdueAt = tz.TZDateTime.now(tz.local).add(overdueDelay);
    const overdueAndroid = AndroidNotificationDetails(
      _feedingOverdueChannelId,
      'Feeding Overdue',
      channelDescription: 'Escalated alert when a feed is overdue',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const overdueIos = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const overdueDetails =
        NotificationDetails(android: overdueAndroid, iOS: overdueIos);
    await _plugin.zonedSchedule(
      _feedingOverdueNotificationId,
      'Feeding overdue',
      'Still no feed logged - baby is past the usual feeding time.',
      overdueAt,
      overdueDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelFeedingReminder() async {
    await _plugin.cancel(_feedingNotificationId);
    await _plugin.cancel(_feedingOverdueNotificationId);
  }

  // ── Sleep reminders ──────────────────────────────────────────────────────
  // Timed off the baby's last wake (the end of the previous sleep). After the
  // wake window a "nap due" reminder fires; _overdueGraceMinutes later, if the
  // baby is still awake, an "overdue" reminder escalates. Starting a sleep
  // cancels both.

  static Future<void> scheduleSleepReminder({
    required DateTime lastWakeTime,
    int wakeWindowMinutes = 120,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('sleep_reminder_enabled') ?? false;

    // Replace any previously scheduled sleep reminders (due + overdue).
    await _plugin.cancel(_sleepNotificationId);
    await _plugin.cancel(_sleepOverdueNotificationId);
    if (!enabled) return;

    final dueDelay =
        lastWakeTime.add(Duration(minutes: wakeWindowMinutes)).difference(DateTime.now());
    if (dueDelay.isNegative) return;

    const dueAndroid = AndroidNotificationDetails(
      _sleepChannelId,
      'Sleep Reminders',
      channelDescription: 'Reminders when it\'s time for a nap',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const dueIos = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const dueDetails = NotificationDetails(android: dueAndroid, iOS: dueIos);

    final hours = wakeWindowMinutes ~/ 60;
    final mins = wakeWindowMinutes % 60;
    final windowStr = hours > 0
        ? (mins > 0 ? '$hours hr ${mins}min' : '$hours hours')
        : '$mins minutes';

    await _plugin.zonedSchedule(
      _sleepNotificationId,
      'Time for a nap',
      'It\'s been $windowStr since the last wake - baby may be ready to sleep.',
      tz.TZDateTime.now(tz.local).add(dueDelay),
      dueDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    // Overdue escalation.
    final overdueDelay = dueDelay + const Duration(minutes: _overdueGraceMinutes);
    const overdueAndroid = AndroidNotificationDetails(
      _sleepOverdueChannelId,
      'Sleep Overdue',
      channelDescription: 'Escalated alert when a nap is overdue',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const overdueDetails =
        NotificationDetails(android: overdueAndroid, iOS: dueIos);
    await _plugin.zonedSchedule(
      _sleepOverdueNotificationId,
      'Nap overdue',
      'Baby has been awake past the usual window - overtired can make settling harder.',
      tz.TZDateTime.now(tz.local).add(overdueDelay),
      overdueDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelSleepReminders() async {
    await _plugin.cancel(_sleepNotificationId);
    await _plugin.cancel(_sleepOverdueNotificationId);
  }

  static Future<bool> isSleepReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('sleep_reminder_enabled') ?? false;
  }

  static Future<int> getSleepWindow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sleep_reminder_window') ?? 120;
  }

  static Future<void> setSleepReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sleep_reminder_enabled', enabled);
    if (!enabled) await cancelSleepReminders();
    await NotificationPrefsSync.push();
  }

  static Future<void> setSleepWindow(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sleep_reminder_window', minutes);
    await NotificationPrefsSync.push();
  }

  /// Schedules a repeating reminder every Friday at 14:00 local time to
  /// finish and share the weekly report.
  static Future<void> scheduleWeeklyReportReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('weekly_report_reminder_enabled') ?? false;
    if (!enabled) return;

    // Replace any previously scheduled reminder.
    await _plugin.cancel(_weeklyReportNotificationId);

    // Next Friday 14:00 in DEVICE-local time. tz.local is UTC (we never call
    // setLocalLocation), so compute the target with Dart's local DateTime and
    // anchor the tz instant via a delta - same trick as the feeding reminder.
    final now = DateTime.now();
    var target = DateTime(now.year, now.month,
        now.day + (DateTime.friday - now.weekday) % 7, 14);
    if (!target.isAfter(now)) {
      target = DateTime(target.year, target.month, target.day + 7, 14);
    }
    final scheduledAt =
        tz.TZDateTime.now(tz.local).add(target.difference(now));

    const androidDetails = AndroidNotificationDetails(
      _weeklyReportChannelId,
      'Weekly Report Reminders',
      channelDescription: 'Friday reminder to finish the weekly report',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _weeklyReportNotificationId,
      'Weekly report time',
      'Most of it is already filled in from the week\'s logs - finish and share it with the parents.',
      scheduledAt,
      details,
      // Inexact keeps us clear of the Android 12+ exact-alarm permission;
      // the report nudge can be a couple of minutes off.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Repeats every Friday at the same time.
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> cancelWeeklyReportReminder() async {
    await _plugin.cancel(_weeklyReportNotificationId);
  }

  static Future<bool> isWeeklyReportReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('weekly_report_reminder_enabled') ?? false;
  }

  /// One-time cleanup for users upgrading from on-device feed/sleep reminders.
  ///
  /// Their phone still has OS-scheduled feeding and sleep notifications from the
  /// old build. Those would fire alongside the new server pushes, so every
  /// overdue feed would buzz twice. Cancel them once and remember we did.
  static Future<void> migrateOffLocalFeedSleepReminders() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('local_feed_sleep_cancelled') ?? false) return;
    await cancelFeedingReminder();
    await cancelSleepReminders();
    await prefs.setBool('local_feed_sleep_cancelled', true);
  }

  static Future<void> setWeeklyReportReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weekly_report_reminder_enabled', enabled);
    if (enabled) {
      await scheduleWeeklyReportReminder();
    } else {
      await cancelWeeklyReportReminder();
    }
    await NotificationPrefsSync.push();
  }

  static Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('feeding_reminder_enabled') ?? false;
  }

  static Future<int> getReminderInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('feeding_reminder_interval') ?? 180;
  }

  static Future<void> setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feeding_reminder_enabled', enabled);
    if (!enabled) {
      await cancelFeedingReminder();
    }
    // Feed reminders are sent by the check-overdue cron now, so the server has
    // to hear about this change or nothing happens.
    await NotificationPrefsSync.push();
  }

  static Future<void> setReminderInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('feeding_reminder_interval', minutes);
    await NotificationPrefsSync.push();
  }

  // ── Medication reminders ────────────────────────────────────────────────

  static Future<bool> isMedicationReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('medication_reminder_enabled') ?? false;
  }

  static Future<void> setMedicationReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('medication_reminder_enabled', enabled);
    if (!enabled) await cancelAllMedicationReminders();
    await NotificationPrefsSync.push();
  }

  static Future<void> cancelAllMedicationReminders() async {
    for (var i = 0; i < _maxMedReminders; i++) {
      await _plugin.cancel(_medicationIdBase + i);
    }
  }

  /// Schedule "medicine due" reminders for the given meds. Each entry is the
  /// med name + the time the next dose is due. Past/None entries are skipped.
  /// Replaces any previously scheduled medication reminders.
  static Future<void> scheduleMedicationReminders(
    List<({String name, DateTime dueAt})> due,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('medication_reminder_enabled') ?? false;
    await cancelAllMedicationReminders();
    if (!enabled) return;

    const androidDetails = AndroidNotificationDetails(
      _medicationChannelId,
      'Medication Reminders',
      channelDescription: 'Reminders when a scheduled medicine is due',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final now = DateTime.now();
    var i = 0;
    for (final med in due) {
      if (i >= _maxMedReminders) break;
      final delay = med.dueAt.difference(now);
      if (delay.isNegative) continue; // already due / past — don't fire late
      final scheduledAt = tz.TZDateTime.now(tz.local).add(delay);
      await _plugin.zonedSchedule(
        _medicationIdBase + i,
        'Medicine due',
        'It\'s time for ${med.name}.',
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      i++;
    }
  }
}
