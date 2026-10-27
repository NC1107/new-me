import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../health/background_health_bridge.dart';
import 'caches.dart';
import 'local_prefs.dart';
import 'update_gate.dart';

/// One key holding the whole session as JSON, so a read or write is never half applied.
const kSessionKey = 'session';

class Session {
  const Session({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.userName,
    required this.color,
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    baseUrl: j['baseUrl'] as String,
    token: j['token'] as String,
    userId: (j['userId'] as num).toInt(),
    userName: j['userName'] as String,
    color: j['color'] as String,
  );

  final String baseUrl;
  final String token;
  final int userId;
  final String userName;

  /// Accent preset id, see accentById.
  final String color;

  Session copyWith({String? userName, String? color}) => Session(
    baseUrl: baseUrl,
    token: token,
    userId: userId,
    userName: userName ?? this.userName,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'userId': userId,
    'userName': userName,
    'color': color,
    'token': token,
  };
}

class SessionState {
  const SessionState({this.session, this.restored = false, this.signedOutFrom});

  final Session? session;

  /// False until storage has been read, so startup shows a blank frame instead of flashing
  /// onboarding.
  final bool restored;

  /// The server a forced sign-out came from; onboarding prefills it and explains what happened.
  final String? signedOutFrom;
}

typedef ApiClientFactory = ApiClient Function({
  required String baseUrl,
  String? token,
  void Function()? onUnauthorized,
  void Function()? onUpdateRequired,
});

/// The seam tests override to put a stub HTTP adapter under every client.
final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) =>
      ({required baseUrl, token, onUnauthorized, onUpdateRequired}) => ApiClient(
        baseUrl: baseUrl,
        token: token,
        onUnauthorized: onUnauthorized,
        onUpdateRequired: onUpdateRequired,
      ),
);

class SessionController extends Notifier<SessionState> {
  SessionController() : _seed = null;

  @visibleForTesting
  SessionController.seeded(Session? initial)
    : _seed = SessionState(session: initial, restored: true);

  final SessionState? _seed;

  final _secure = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

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
    Session? session;
    try {
      final raw = await _secure.read(key: kSessionKey);
      if (raw != null) session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (e) {
      debugPrint('[NEWME] discarding unreadable session: $e');
    }
    state = SessionState(session: session, restored: true);
  }

  Future<void> signIn(Session session) async {
    await _secure.write(key: kSessionKey, value: jsonEncode(session.toJson()));
    state = SessionState(session: session, restored: true);
  }

  /// Mirrors a saved profile edit into the stored session, which drives the accent.
  Future<void> updateProfile({required String name, required String color}) async {
    final current = state.session;
    if (current == null) return;
    final updated = current.copyWith(userName: name, color: color);
    await _secure.write(key: kSessionKey, value: jsonEncode(updated.toJson()));
    state = SessionState(session: updated, restored: true);
  }

  /// Leaves the server. A forced sign-out (the server rejected the token) keeps the server
  /// address for onboarding and skips revoking the device, which the server already did.
  Future<void> signOut({bool forced = false}) async {
    final leaving = state.session;
    if (leaving == null) return;
    state = SessionState(restored: true, signedOutFrom: forced ? leaving.baseUrl : null);
    await _secure.delete(key: kSessionKey);
    // The health controller may already be gone, and a stale native token must not outlive this.
    unawaited(ref.read(backgroundHealthBridgeProvider).clear());
    await LocalPrefs.clearForSignOut();
    await clearResponseCaches();
    if (!forced) await _revokeDevice(leaving);
  }

  Future<void> _revokeDevice(Session leaving) async {
    try {
      final client = ref.read(apiClientFactoryProvider)(
        baseUrl: leaving.baseUrl,
        token: leaving.token,
      );
      await client.deleteDevice().timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      debugPrint('[NEWME] device revoke skipped: $e');
    }
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Rebuilt only when the credentials change, so a renamed profile does not reload every screen.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final credentials = ref.watch(
    sessionProvider.select((s) => (baseUrl: s.session?.baseUrl, token: s.session?.token)),
  );
  final (:baseUrl, :token) = credentials;
  if (baseUrl == null || token == null) return null;
  return ref.watch(apiClientFactoryProvider)(
    baseUrl: baseUrl,
    token: token,
    // A late 401 for a token that has since been replaced must not end the new session.
    onUnauthorized: () {
      if (ref.read(sessionProvider).session?.token != token) return;
      unawaited(ref.read(sessionProvider.notifier).signOut(forced: true));
    },
    onUpdateRequired: () => ref.read(updateGateProvider.notifier).require(),
  );
});
