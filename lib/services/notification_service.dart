import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _feedingChannelId = 'feeding_reminders';
  static const _feedingNotificationId = 1001;

  static Future<void> initialize() async {
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

  static Future<void> scheduleFeedingReminder({
    required DateTime lastFeedTime,
    int intervalMinutes = 180,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('feeding_reminder_enabled') ?? false;
    if (!enabled) return;

    // Cancel existing reminder
    await _plugin.cancel(_feedingNotificationId);

    final triggerTime = lastFeedTime.add(Duration(minutes: intervalMinutes));

    // Don't schedule if trigger time is in the past
    if (triggerTime.isBefore(DateTime.now())) return;

    final delay = triggerTime.difference(DateTime.now());

    // Use Future.delayed as a simple scheduling mechanism
    // (avoids timezone package dependency)
    Future.delayed(delay, () async {
      final currentPrefs = await SharedPreferences.getInstance();
      final stillEnabled = currentPrefs.getBool('feeding_reminder_enabled') ?? false;
      if (!stillEnabled) return;

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

      final hours = intervalMinutes ~/ 60;
      final mins = intervalMinutes % 60;
      final timeStr = hours > 0
          ? (mins > 0 ? '$hours hr ${mins}min' : '$hours hours')
          : '$mins minutes';

      await _plugin.show(
        _feedingNotificationId,
        'Time to feed! 🍼',
        'It\'s been $timeStr since the last feed.',
        details,
      );
    });
  }

  static Future<void> cancelFeedingReminder() async {
    await _plugin.cancel(_feedingNotificationId);
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
