import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_plan.dart';

/// The one seam to the OS notification centre, so the rules above it can be tested with a fake.
abstract class ReminderScheduler {
  /// [onTap] fires when the person taps a reminder, whether the app was running or not.
  Future<void> init({required VoidCallback onTap});

  Future<bool> isAllowed();

  /// Shows the system prompt the first time; afterwards iOS answers without asking.
  Future<bool> requestPermission();

  Future<void> schedule(Reminder reminder);

  Future<void> cancel(int id);
}

/// For platforms without local notifications. It reports permission as granted so the settings
/// UI stays reviewable in a browser.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> init({required VoidCallback onTap}) async {}

  @override
  Future<bool> isAllowed() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(Reminder reminder) async {}

  @override
  Future<void> cancel(int id) async {}
}

class LocalNotificationsScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> init({required VoidCallback onTap}) async {
    tzdata.initializeTimeZones();
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(zone));
    } on Object catch (e) {
      debugPrint('[NEWME] reminder time zone unavailable, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The prompt belongs to the onboarding step and the Me page, never to launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onTap(),
    );
  }

  @override
  Future<bool> isAllowed() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return (await ios?.checkPermissions())?.isEnabled ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> schedule(Reminder reminder) {
    final at = reminder.at;
    return _plugin.zonedSchedule(
      id: reminder.id,
      scheduledDate: tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
      notificationDetails: const NotificationDetails(iOS: DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: reminder.title,
      body: reminder.body,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? LocalNotificationsScheduler()
      : const NoopReminderScheduler(),
);
