import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shell/home_tab.dart';
import '../reminders/reminder_plan.dart';
import '../reminders/reminder_scheduler.dart';
import 'clock.dart';
import 'local_prefs.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// Lets a tapped notification unwind any pushed page back to the tab bar.
final rootNavigatorKey = GlobalKey<NavigatorState>();

@immutable
class ReminderSettings {
  const ReminderSettings({
    this.loaded = false,
    this.enabled = false,
    this.minutes = kDefaultReminderMinutes,
    this.allowed = false,
  });

  final bool loaded;

  /// What the person asked for; the reminder only fires when the system also allows it.
  final bool enabled;
  final int minutes;
  final bool allowed;

  bool get active => enabled && allowed;

  /// The person wants reminders but the system says no, so only iOS Settings can fix it.
  bool get blocked => enabled && !allowed;

  ReminderSettings copyWith({bool? loaded, bool? enabled, int? minutes, bool? allowed}) =>
      ReminderSettings(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        minutes: minutes ?? this.minutes,
        allowed: allowed ?? this.allowed,
      );
}

class ReminderController extends Notifier<ReminderSettings> {
  Future<void> _queue = Future.value();

  /// Changes made before saved preferences load would be overwritten by them.
  Future<void> _hydrated = Future.value();

  ReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  /// Completes once the scheduler is set up and the saved choices are loaded.
  Future<void> get ready => _hydrated;

  @override
  ReminderSettings build() {
    ref.listen(todayProvider, (_, _) => _reschedule());
    ref.listen(meProvider.select((m) => m.value?.data.schedule), (_, _) => _reschedule());
    ref.listen(sessionProvider.select((s) => s.session?.userId), (prev, next) {
      if (next != null || prev == null) return;
      state = const ReminderSettings(loaded: true);
      unawaited(_enqueue(_cancelAll));
    });
    _hydrated = _hydrate();
    return const ReminderSettings();
  }

  Future<void> _hydrate() async {
    try {
      await _scheduler.init(onTap: _openToday);
      state = ReminderSettings(
        loaded: true,
        enabled: await LocalPrefs.remindersEnabled(),
        minutes: await LocalPrefs.reminderMinutes() ?? kDefaultReminderMinutes,
        allowed: await _scheduler.isAllowed(),
      );
    } on Object catch (e) {
      debugPrint('[NEWME] reminders unavailable: $e');
      state = state.copyWith(loaded: true);
    }
    _reschedule();
  }

  void _openToday() {
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(homeTabProvider.notifier).select(HomeTab.today);
  }

  /// Shows the system prompt (once) without turning the evening reminder on, for features such
  /// as push that only need the permission. Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    await _hydrated;
    final allowed = await _scheduler.requestPermission();
    state = state.copyWith(allowed: allowed);
    _reschedule();
    return allowed;
  }

  /// Turns reminders on at [minutes] (or the saved time), asking the system the first time.
  /// Returns whether the system allows them.
  Future<bool> enable({int? minutes}) async {
    await _hydrated;
    final allowed = await _scheduler.requestPermission();
    final chosen = minutes ?? state.minutes;
    state = state.copyWith(enabled: true, allowed: allowed, minutes: chosen);
    await LocalPrefs.setRemindersEnabled(true);
    await LocalPrefs.setReminderMinutes(chosen);
    _reschedule();
    return allowed;
  }

  Future<void> disable() async {
    await _hydrated;
    state = state.copyWith(enabled: false);
    await LocalPrefs.setRemindersEnabled(false);
    _reschedule();
  }

  Future<void> setMinutes(int minutes) async {
    await _hydrated;
    state = state.copyWith(minutes: minutes);
    await LocalPrefs.setReminderMinutes(minutes);
    _reschedule();
  }

  /// The person may have flipped the switch in iOS Settings while the app was away.
  Future<void> refreshPermission() async {
    if (!state.loaded) return;
    final allowed = await _scheduler.isAllowed();
    if (allowed == state.allowed) return;
    state = state.copyWith(allowed: allowed);
    _reschedule();
  }

  void _reschedule() => unawaited(_enqueue(_apply));

  Future<void> _enqueue(Future<void> Function() job) => _queue = _queue.then((_) async {
    try {
      await job();
    } on Object catch (e) {
      debugPrint('[NEWME] reminder scheduling failed: $e');
    }
  });

  Future<void> _cancelAll() async {
    await _scheduler.cancel(kTonightReminderId);
    await _scheduler.cancel(kTomorrowReminderId);
  }

  Future<void> _apply() async {
    final settings = state;
    final signedIn = ref.read(sessionProvider).session != null;
    if (!settings.loaded || !settings.active || !signedIn) {
      if (settings.loaded) await _cancelAll();
      return;
    }
    final plan = planReminders(
      now: ref.read(clockProvider)(),
      minutes: settings.minutes,
      today: ref.read(todayProvider).value?.data,
      schedule: ref.read(meProvider).value?.data.schedule,
    );
    for (final MapEntry(:key, :value) in plan.entries) {
      if (value == null) {
        await _scheduler.cancel(key);
      } else {
        await _scheduler.schedule(value);
      }
    }
  }
}

final remindersProvider = NotifierProvider<ReminderController, ReminderSettings>(
  ReminderController.new,
);
