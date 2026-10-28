import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../companion/companion_bridge.dart';
import '../companion/companion_snapshot.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// Keeps the widgets and the Watch showing what Today shows. Every change to Today or the
/// session writes a new snapshot; an unchanged one is not sent again, because each write
/// reloads every widget timeline.
class CompanionController extends Notifier<void> {
  String? _sent;

  CompanionBridge get _bridge => ref.read(companionBridgeProvider);

  @override
  void build() {
    _sent = null;
    ref.listen(todayProvider, (_, _) => _publish());
    ref.listen(sessionProvider.select((s) => s.session), (_, _) => _publish());
    ref.listen(meProvider.select((m) => m.value?.data.user.timezone), (_, _) => _publish());
    final bridge = _bridge
      ..onRemoteChange(() => unawaited(ref.read(todayProvider.notifier).refresh()));
    ref.onDispose(() => bridge.onRemoteChange(null));
    _publish();
  }

  void _publish() {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      if (_sent != null) unawaited(_bridge.clear());
      _sent = null;
      return;
    }
    final cached = ref.read(todayProvider).value;
    // Riverpod keeps the previous person's value while Today reloads for a new session.
    if (cached == null || cached.userId != session.userId) return;
    final json = jsonEncode(
      companionSnapshot(
        session: session,
        today: cached.data,
        timezone: ref.read(meProvider).value?.data.user.timezone,
      ),
    );
    if (json == _sent) return;
    _sent = json;
    unawaited(_bridge.update(json));
  }
}

final companionProvider = NotifierProvider<CompanionController, void>(CompanionController.new);
