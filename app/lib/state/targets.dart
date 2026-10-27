import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// GET /api/targets: every research-backed target with its formula and sources.
class TargetsNotifier extends CachedNotifier<TargetsReport> {
  @override
  ResponseCache<TargetsReport> get cache => targetsCache;

  @override
  Future<TargetsReport> fetch(ApiClient client) => client.targets();

  /// Applies [keys] all or nothing. The profile and Today follow at once, because the food card
  /// and the quest targets read from them; failures are thrown for the page to show.
  Future<List<String>> apply(List<String> keys) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final result = await client.applyTargets(keys);
    await ref.read(meProvider.notifier).replace(result.me);
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
    await refresh();
    return result.applied;
  }
}

final targetsProvider = AsyncNotifierProvider<TargetsNotifier, Cached<TargetsReport>>(
  TargetsNotifier.new,
);
