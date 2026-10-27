import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

const _kSessionPref = 'session';
const _kTokenKey = 'token';

class Session {
  const Session({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.userName,
    required this.color,
  });

  final String baseUrl;
  final String token;
  final int userId;
  final String userName;

  /// Accent preset id, see accentById.
  final String color;

  Map<String, dynamic> toPrefsJson() => {
    'baseUrl': baseUrl,
    'userId': userId,
    'userName': userName,
    'color': color,
  };
}

class SessionState {
  const SessionState({this.session, this.restored = false});

  final Session? session;

  /// False until storage has been read, so startup shows a blank frame instead of flashing
  /// onboarding.
  final bool restored;
}

class SessionController extends Notifier<SessionState> {
  SessionController() : _seed = null;

  @visibleForTesting
  SessionController.seeded(Session? initial)
    : _seed = SessionState(session: initial, restored: true);

  final SessionState? _seed;

  final _secure = const FlutterSecureStorage();

  @override
  SessionState build() {
    final seed = _seed;
    if (seed != null) return seed;
    _restoring = _load();
    return const SessionState();
  }

  Future<void> _restoring = Future.value();

  @visibleForTesting
  Future<void> get restoreDone => _restoring;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _secure.read(key: _kTokenKey);
    final raw = prefs.getString(_kSessionPref);
    Session? session;
    if (token != null && raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        session = Session(
          baseUrl: j['baseUrl'] as String,
          token: token,
          userId: (j['userId'] as num).toInt(),
          userName: j['userName'] as String,
          color: j['color'] as String,
        );
      } on Object catch (e) {
        debugPrint('[NEWME] discarding unreadable session: $e');
      }
    }
    state = SessionState(session: session, restored: true);
  }

  Future<void> signIn(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _kTokenKey, value: session.token);
    await prefs.setString(_kSessionPref, jsonEncode(session.toPrefsJson()));
    state = SessionState(session: session, restored: true);
  }

  Future<void> signOut() async {
    state = const SessionState(restored: true);
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: _kTokenKey);
    await prefs.remove(_kSessionPref);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

final apiClientProvider = Provider<ApiClient?>((ref) {
  final session = ref.watch(sessionProvider).session;
  if (session == null) return null;
  return ApiClient(
    baseUrl: session.baseUrl,
    token: session.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).signOut(),
  );
});
