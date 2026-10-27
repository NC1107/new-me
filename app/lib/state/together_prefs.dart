import 'package:shared_preferences/shared_preferences.dart';

const _kCheersSent = 'togetherCheersSent';
const _kCheersDismissed = 'togetherCheersDismissed';
const _kCelebratedChallenge = 'togetherCelebratedChallenge';
const _kCelebratedReward = 'togetherCelebratedReward';

/// Per-install memory for the Together features: what this phone already sent, dismissed or
/// celebrated. The server is the source of truth for everything else.
class TogetherPrefs {
  const TogetherPrefs._();

  static Future<Set<String>> cheersSent() async =>
      ((await SharedPreferences.getInstance()).getStringList(_kCheersSent) ?? const []).toSet();

  static Future<void> setCheersSent(Set<String> keys) async =>
      (await SharedPreferences.getInstance()).setStringList(_kCheersSent, keys.toList());

  static Future<Set<String>> cheersDismissed() async =>
      ((await SharedPreferences.getInstance()).getStringList(_kCheersDismissed) ?? const [])
          .toSet();

  static Future<void> setCheersDismissed(Set<String> keys) async =>
      (await SharedPreferences.getInstance()).setStringList(_kCheersDismissed, keys.toList());

  /// The `endsOn` date of the last challenge whose celebration played.
  static Future<String?> celebratedChallenge() async =>
      (await SharedPreferences.getInstance()).getString(_kCelebratedChallenge);

  static Future<void> setCelebratedChallenge(String endsOn) async =>
      (await SharedPreferences.getInstance()).setString(_kCelebratedChallenge, endsOn);

  static Future<int?> celebratedReward() async =>
      (await SharedPreferences.getInstance()).getInt(_kCelebratedReward);

  static Future<void> setCelebratedReward(int id) async =>
      (await SharedPreferences.getInstance()).setInt(_kCelebratedReward, id);

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_kCheersSent);
    await prefs.remove(_kCheersDismissed);
    await prefs.remove(_kCelebratedChallenge);
    await prefs.remove(_kCelebratedReward);
  }
}
