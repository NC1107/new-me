import 'dart:ui';

import 'package:newme/reminders/reminder_plan.dart';
import 'package:newme/reminders/reminder_scheduler.dart';

/// Records what would reach the OS notification centre.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.allowed = true, this.grantsOnRequest = true});

  bool allowed;
  final bool grantsOnRequest;
  int permissionRequests = 0;
  VoidCallback? onTap;

  /// What is pending right now, by id.
  final Map<int, Reminder> pending = {};

  /// Every schedule and cancel call in order, for asserting churn.
  final List<String> calls = [];

  @override
  Future<void> init({required VoidCallback onTap}) async => this.onTap = onTap;

  @override
  Future<bool> isAllowed() async => allowed;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    allowed = grantsOnRequest;
    return allowed;
  }

  @override
  Future<void> schedule(Reminder reminder) async {
    calls.add('schedule ${reminder.id}');
    pending[reminder.id] = reminder;
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel $id');
    pending.remove(id);
  }

  @override
  Future<void> useDeviceTimezone() async {
    calls.add('timezone');
  }

  @override
  Future<List<int>> pendingIds() async => pending.keys.toList();
}
