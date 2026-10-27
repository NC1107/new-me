import 'package:shared_preferences/shared_preferences.dart';

const _kHealthPrompted = 'healthPrompted';
const _kLastSyncedAt = 'lastSyncedAt';
const _kLastLogKind = 'lastLogKind';
const _kCountUpDate = 'countUpDate';
const _kDeviceTimezone = 'deviceTimezone';

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

  /// The local date the score ring last counted up on, so it only does that once a day.
  static Future<String?> countUpDate() async =>
      (await SharedPreferences.getInstance()).getString(_kCountUpDate);

  static Future<void> setCountUpDate(String date) async =>
      (await SharedPreferences.getInstance()).setString(_kCountUpDate, date);

  /// The device zone last sent to the server, to tell a moved phone from a zone picked by hand.
  static Future<String?> deviceTimezone() async =>
      (await SharedPreferences.getInstance()).getString(_kDeviceTimezone);

  static Future<void> setDeviceTimezone(String zone) async =>
      (await SharedPreferences.getInstance()).setString(_kDeviceTimezone, zone);

  static Future<void> clearForSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastSyncedAt);
    await prefs.remove(_kLastLogKind);
    await prefs.remove(_kCountUpDate);
    await prefs.remove(_kDeviceTimezone);
  }
}
