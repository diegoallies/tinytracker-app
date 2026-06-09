import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _feedingChannelId = 'feeding_reminders';
  static const _feedingNotificationId = 1001;
  static const _weeklyReportChannelId = 'weekly_report_reminders';
  static const _weeklyReportNotificationId = 1002;

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
  /// backgrounded or killed — the old Future.delayed approach did not).
  static Future<void> scheduleFeedingReminder({
    required DateTime lastFeedTime,
    int intervalMinutes = 180,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('feeding_reminder_enabled') ?? false;
    if (!enabled) return;

    // Replace any previously scheduled reminder.
    await _plugin.cancel(_feedingNotificationId);

    final triggerTime = lastFeedTime.add(Duration(minutes: intervalMinutes));
    final delay = triggerTime.difference(DateTime.now());
    if (delay.isNegative) return;

    // Anchoring to tz now + delay sidesteps needing the device's named
    // timezone — the instant is correct even if tz.local is UTC.
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
      'Time to feed! 🍼',
      'It\'s been $timeStr since the last feed.',
      scheduledAt,
      details,
      // Inexact keeps us clear of the Android 12+ exact-alarm permission;
      // a feeding nudge can be a couple of minutes off.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelFeedingReminder() async {
    await _plugin.cancel(_feedingNotificationId);
  }

  /// Schedules a repeating reminder every Friday at 14:00 local time to
  /// finish and share the weekly report.
  static Future<void> scheduleWeeklyReportReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('weekly_report_reminder_enabled') ?? false;
    if (!enabled) return;

    // Replace any previously scheduled reminder.
    await _plugin.cancel(_weeklyReportNotificationId);

    // Next Friday 14:00 (day-component arithmetic keeps the hour DST-safe).
    final now = tz.TZDateTime.now(tz.local);
    var scheduledAt = tz.TZDateTime(tz.local, now.year, now.month,
        now.day + (DateTime.friday - now.weekday) % 7, 14);
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = tz.TZDateTime(
          tz.local, scheduledAt.year, scheduledAt.month, scheduledAt.day + 7, 14);
    }

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
      'Weekly report time 📋',
      'Most of it is already filled in from the week\'s logs — finish and share it with the parents.',
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

  static Future<void> setWeeklyReportReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weekly_report_reminder_enabled', enabled);
    if (enabled) {
      await scheduleWeeklyReportReminder();
    } else {
      await cancelWeeklyReportReminder();
    }
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
  }

  static Future<void> setReminderInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('feeding_reminder_interval', minutes);
  }
}
