import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../features/shell/home_tab.dart';
import '../push/push_bridge.dart';
import 'board.dart';
import 'reminders.dart';
import 'session.dart';
import 'today.dart';

/// Registers this phone for push once the person is signed in and has allowed notifications,
/// sends the token to the server whenever it appears or changes, and routes a tapped push.
class PushController extends Notifier<String?> {
  String? _sent;
  bool _registered = false;
  bool _listening = false;

  late PushBridge _bridge;

  /// The last token iOS handed over, or null before one arrives.
  @override
  String? build() {
    _bridge = ref.read(pushBridgeProvider);
    ref.onDispose(() {
      if (_listening) _bridge.stopListening();
    });
    ref.listen(
      sessionProvider.select((s) => s.session?.userId),
      (prev, next) => next == null ? _signedOut() : unawaited(_sync()),
      fireImmediately: true,
    );
    ref.listen(
      remindersProvider.select((s) => s.loaded && s.allowed),
      (_, _) => unawaited(_sync()),
    );
    ref.listen(apiClientProvider, (_, _) => unawaited(_deliver()));
    return null;
  }

  Future<void> _sync() async {
    final signedIn = ref.read(sessionProvider).session != null;
    final reminders = ref.read(remindersProvider);
    if (!signedIn || !reminders.loaded || !reminders.allowed) return;
    if (!_listening) {
      _listening = true;
      _bridge.listen(onToken: _onToken, onTap: _onTap, onError: _onError);
      final launch = await _bridge.takeLaunchTap();
      if (launch != null) _onTap(launch);
    }
    if (_registered) return;
    _registered = true;
    await _bridge.register();
  }

  void _onToken(String token) {
    state = token;
    unawaited(_deliver());
  }

  void _onError(String message) => debugPrint('[NEWME] push registration failed: $message');

  Future<void> _deliver() async {
    final token = state;
    final client = ref.read(apiClientProvider);
    if (token == null || client == null || token == _sent) return;
    try {
      await client.putPushToken(token);
      _sent = token;
    } on ApiException catch (e) {
      debugPrint('[NEWME] push token not saved: $e');
    }
  }

  void _signedOut() {
    _sent = null;
    _registered = false;
    state = null;
    if (_listening) unawaited(_bridge.unregister());
  }

  /// Every push event concerns the two of you, so a tap lands on Us with fresh numbers.
  void _onTap(String kind) {
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(homeTabProvider.notifier).select(HomeTab.board);
    if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
  }
}

final pushProvider = NotifierProvider<PushController, String?>(PushController.new);
