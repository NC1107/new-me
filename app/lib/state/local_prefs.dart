import 'package:shared_preferences/shared_preferences.dart';

const _kHealthPrompted = 'healthPrompted';
const _kLastSyncedAt = 'lastSyncedAt';
const _kLastLogKind = 'lastLogKind';
const _kCelebratedDate = 'celebratedDate';
const _kDeviceTimezone = 'deviceTimezone';
const _kRemindersEnabled = 'remindersEnabled';
const _kReminderMinutes = 'reminderMinutes';

/// Non-secret, per-install values. The Keychain blob in session.dart holds everything secret.
class LocalPrefs {
  const LocalPrefs._();

  static Future<bool> healthPrompted() async =>
      (await SharedPreferences.getInstance()).getBool(_kHealthPrompted) ?? false;

  static Future<void> setHealthPrompted() async =>
      (await SharedPreferences.getInstance()).setBool(_kHealthPrompted, true);

  static Future<DateTime?> lastSyncedAt() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kLastSyncedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> setLastSyncedAt(DateTime at) async => (await SharedPreferences.getInstance())
      .setString(_kLastSyncedAt, at.toUtc().toIso8601String());

  static Future<String?> lastLogKind() async =>
      (await SharedPreferences.getInstance()).getString(_kLastLogKind);

  static Future<void> setLastLogKind(String kind) async =>
      (await SharedPreferences.getInstance()).setString(_kLastLogKind, kind);

  /// The local date the day-counted celebration last played on, so it plays once a day.
  static Future<String?> celebratedDate() async =>
      (await SharedPreferences.getInstance()).getString(_kCelebratedDate);

  static Future<void> setCelebratedDate(String date) async =>
      (await SharedPreferences.getInstance()).setString(_kCelebratedDate, date);

  /// The device zone last sent to the server, to tell a moved phone from a zone picked by hand.
  static Future<String?> deviceTimezone() async =>
      (await SharedPreferences.getInstance()).getString(_kDeviceTimezone);

  static Future<void> setDeviceTimezone(String zone) async =>
      (await SharedPreferences.getInstance()).setString(_kDeviceTimezone, zone);

  static Future<bool> remindersEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kRemindersEnabled) ?? false;

  static Future<void> setRemindersEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kRemindersEnabled, value);

  /// Minutes after local midnight, or null while the person has not picked a time.
  static Future<int?> reminderMinutes() async =>
      (await SharedPreferences.getInstance()).getInt(_kReminderMinutes);

  static Future<void> setReminderMinutes(int minutes) async =>
      (await SharedPreferences.getInstance()).setInt(_kReminderMinutes, minutes);

  static Future<void> clearForSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastSyncedAt);
    await prefs.remove(_kLastLogKind);
    await prefs.remove(_kCelebratedDate);
    await prefs.remove(_kDeviceTimezone);
    await prefs.remove(_kRemindersEnabled);
    await prefs.remove(_kReminderMinutes);
  }
}
