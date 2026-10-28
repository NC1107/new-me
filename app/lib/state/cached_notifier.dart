import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'cached_resource.dart';
import 'clock.dart';
import 'session.dart';

/// A server read that survives the server being down: the last good response is stored and
/// served under an offline banner when the network or a 5xx gets in the way.
abstract class CachedNotifier<T> extends AsyncNotifier<Cached<T>> {
  ResponseCache<T> get cache;

  /// Bumped by every refresh and replace, so a response that left earlier never lands on top of
  /// a newer one.
  int _generation = 0;

  Future<T> fetch(ApiClient client);

  @override
  Future<Cached<T>> build() {
    ref.watch(apiClientProvider);
    return _load();
  }

  Future<Cached<T>> _load() async {
    final session = ref.read(sessionProvider).session;
    final client = ref.read(apiClientProvider);
    if (session == null || client == null) throw StateError('Not signed in');
    try {
      final value = await fetch(client);
      if (ref.mounted && ref.read(sessionProvider).session?.userId == session.userId) {
        await cache.write(
          value,
          userId: session.userId,
          baseUrl: session.baseUrl,
          at: ref.read(clockProvider)(),
        );
      }
      return Cached(value, userId: session.userId);
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.offline) rethrow;
      final stored = await cache.read(userId: session.userId, baseUrl: session.baseUrl);
      if (stored == null) rethrow;
      return stored;
    }
  }

  /// Reloads without dropping the value on screen; a failure keeps it beneath the error.
  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final loaded = await _load();
      if (ref.mounted && generation == _generation) state = AsyncData(loaded);
    } on Object catch (e, st) {
      if (ref.mounted && generation == _generation) state = AsyncError<Cached<T>>(e, st);
    }
  }

  /// The screen changes at once and the cache catches up, so a tap never waits on storage.
  Future<void> replace(T value) async {
    if (!ref.mounted) return;
    final session = ref.read(sessionProvider).session;
    _generation++;
    state = AsyncData(Cached(value, userId: session?.userId));
    if (session != null) {
      await cache.write(
        value,
        userId: session.userId,
        baseUrl: session.baseUrl,
        at: ref.read(clockProvider)(),
      );
    }
  }
}
