import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Shown on a slim banner when a screen is drawn from the last good response.
class OfflineInfo {
  const OfflineInfo({required this.updatedAt});

  final DateTime updatedAt;
}

/// A value plus, when it came from the cache, how old it is.
class Cached<T> {
  const Cached(this.data, {this.offline});

  final T data;
  final OfflineInfo? offline;
}

/// The last good response of one endpoint, tied to the user and server that fetched it.
class ResponseCache<T> {
  const ResponseCache({required this.key, required this.fromJson, required this.toJson});

  final String key;
  final T Function(Json) fromJson;
  final Json Function(T) toJson;

  Future<void> write(
    T value, {
    required int userId,
    required String baseUrl,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'userId': userId,
        'baseUrl': baseUrl,
        'updatedAt': at.toUtc().toIso8601String(),
        'data': toJson(value),
      }),
    );
  }

  Future<Cached<T>?> read({required int userId, required String baseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Json;
      if (j['userId'] != userId || j['baseUrl'] != baseUrl) return null;
      final updatedAt = DateTime.parse(j['updatedAt'] as String);
      return Cached(fromJson(j['data'] as Json), offline: OfflineInfo(updatedAt: updatedAt));
    } on Object {
      return null;
    }
  }

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(key);
}
