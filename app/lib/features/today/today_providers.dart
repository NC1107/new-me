import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/session.dart';

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
