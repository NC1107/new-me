import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import 'habit_reminder_plan.dart';
import 'reminder_plan.dart';
import 'reminder_scheduler.dart';

const kHabitCategory = 'habit';
const kActionDone = 'habit.done';
const kActionSnooze = 'habit.snooze';

/// Runs when Done or Snooze is pressed on a habit reminder, possibly with the app not running.
/// This is a separate isolate with no providers, so it reads the stored session itself.
@pragma('vm:entry-point')
Future<void> habitNotificationBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final scheduler = LocalNotificationsScheduler();
  await scheduler.prepare();
  await handleHabitAction(
    actionId: response.actionId,
    payload: response.payload,
    loadSession: loadStoredSession,
    clientFor: (session) => ApiClient(baseUrl: session.baseUrl, token: session.token),
    schedule: scheduler.schedule,
    now: DateTime.now,
  );
}

/// The logic of the two actions with every outside effect passed in, so it can be tested.
Future<void> handleHabitAction({
  required String? actionId,
  required String? payload,
  required Future<Session?> Function() loadSession,
  required ApiClient Function(Session) clientFor,
  required Future<void> Function(Reminder) schedule,
  required DateTime Function() now,
}) async {
  final parsed = HabitReminderPayload.tryParse(payload);
  if (parsed == null) return;
  if (actionId == kActionSnooze) {
    await schedule(snoozedReminder(payload: parsed, now: now()));
    return;
  }
  if (actionId != kActionDone) return;

  final session = await loadSession();
  if (session == null) return;
  try {
    await clientFor(session)
        .markHabitSlot(parsed.habitId, parsed.date, slot: parsed.slot, done: true);
  } on ApiException catch (e) {
    debugPrint('[NEWME] habit done from notification failed: $e');
    // A day that closed or a habit that went away will not work on a retry either.
    if (e.kind != ApiErrorKind.offline) return;
    await schedule(
      Reminder(
        id: habitSnoozeId(parsed.habitId, parsed.slot),
        at: now().add(const Duration(minutes: 1)),
        title: parsed.title,
        body: 'Could not save that. Tap Done to try again.',
        actionable: true,
        payload: parsed.encode(),
      ),
    );
  }
}
