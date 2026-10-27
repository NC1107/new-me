import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/session.dart';
import '../../state/today.dart';

/// The last seven days of body weight, for the Body card's trend arrow. Null when the server has
/// nothing or cannot be reached, which simply leaves the arrow out.
final weightTrendProvider = FutureProvider.autoDispose<HealthTrend?>((ref) async {
  // A new Health sync can add a weigh-in, so the trend follows the day's sync time.
  ref.watch(todayProvider.select((t) => t.value?.data.health.syncedAt));
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  try {
    return await client.healthTrends('weight_kg', 7);
  } on ApiException {
    return null;
  }
});

/// The other person on the board, or null while it loads or before they have joined.
final partnerProvider = Provider<BoardUser?>((ref) {
  final me = ref.watch(sessionProvider.select((s) => s.session?.userId));
  final users = ref.watch(boardProvider).value?.data.users ?? const <BoardUser>[];
  for (final u in users) {
    if (u.id != me) return u;
  }
  return null;
});

/// My own board row, which carries the last seven days for the week strip.
final ownBoardUserProvider = Provider<BoardUser?>((ref) {
  final me = ref.watch(sessionProvider.select((s) => s.session?.userId));
  final users = ref.watch(boardProvider).value?.data.users ?? const <BoardUser>[];
  for (final u in users) {
    if (u.id == me) return u;
  }
  return null;
});
