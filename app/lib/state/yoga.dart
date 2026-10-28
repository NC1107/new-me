import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'session.dart';

/// GET and PUT /yoga/plan: the weekly yoga plan, this week against it, and the longer-flow offer.
/// Read again after a flow is logged, so "1 of 3" moves at once.
class YogaPlanNotifier extends AsyncNotifier<YogaPlanState> {
  ApiClient get _client {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  @override
  Future<YogaPlanState> build() {
    ref.watch(apiClientProvider);
    return _client.yogaPlan();
  }

  Future<void> save({
    required int daysPerWeek,
    required int flowMinutes,
    bool restartLevel = false,
  }) async {
    final next = await _client.saveYogaPlan(
      daysPerWeek: daysPerWeek,
      flowMinutes: flowMinutes,
      restartLevel: restartLevel,
    );
    state = AsyncData(next);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_client.yogaPlan);
  }
}

final yogaPlanProvider = AsyncNotifierProvider<YogaPlanNotifier, YogaPlanState>(
  YogaPlanNotifier.new,
);
