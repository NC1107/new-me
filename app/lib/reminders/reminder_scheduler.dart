import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'habit_notification_actions.dart';
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

  /// Re-reads the phone's time zone, so reminders planned in wall-clock time land in the zone
  /// the person is in now.
  Future<void> useDeviceTimezone();

  /// The ids of what is pending now, so stale habit reminders can be found and cancelled.
  Future<List<int>> pendingIds();
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

  @override
  Future<void> useDeviceTimezone() async {}

  @override
  Future<List<int>> pendingIds() async => const [];
}

class LocalNotificationsScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  static final _settings = InitializationSettings(
    // The prompt belongs to the onboarding step and the Me page, never to launch.
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          kHabitCategory,
          actions: [
            // No foreground option: iOS runs these in a background isolate, so the lock screen
            // never has to open the app.
            DarwinNotificationAction.plain(kActionDone, 'Done'),
            DarwinNotificationAction.plain(kActionSnooze, 'Snooze 30 min'),
          ],
        ),
      ],
    ),
  );

  /// Sets up the time zone and the plugin without callbacks, which is all a background isolate
  /// needs to schedule a snooze.
  Future<void> prepare({
    DidReceiveNotificationResponseCallback? onResponse,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse,
  }) async {
    tzdata.initializeTimeZones();
    await useDeviceTimezone();
    await _plugin.initialize(
      settings: _settings,
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
  }

  @override
  Future<void> useDeviceTimezone() async {
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(zone));
    } on Object catch (e) {
      debugPrint('[NEWME] reminder time zone unavailable, using UTC: $e');
    }
  }

  @override
  Future<void> init({required VoidCallback onTap}) => prepare(
    // Actions without the foreground option never reach here; only a tap on the note does.
    onResponse: (response) {
      if (response.notificationResponseType == NotificationResponseType.selectedNotification) {
        onTap();
      }
    },
    onBackgroundResponse: habitNotificationBackground,
  );

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
      notificationDetails: NotificationDetails(
        iOS: reminder.actionable
            ? const DarwinNotificationDetails(
                categoryIdentifier: kHabitCategory,
                interruptionLevel: InterruptionLevel.timeSensitive,
              )
            : const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: reminder.title,
      body: reminder.body,
      payload: reminder.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<List<int>> pendingIds() async => [
    for (final r in await _plugin.pendingNotificationRequests()) r.id,
  ];
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? LocalNotificationsScheduler()
      : const NoopReminderScheduler(),
);
