import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'me.dart';
import 'session.dart';
import 'together_prefs.dart';

String _cheerKey(String date, int to, CheerKind kind) => '$date|$to|${kind.name}';

String _dismissKey(String date, Cheer cheer) => '$date|${cheer.from}|${cheer.kind.name}';

/// What this phone remembers about cheers: which kinds it sent today and which received ones
/// were dismissed. Keys carry their date, so yesterday's never match today's.
@immutable
class CheerMemoryState {
  const CheerMemoryState({this.loaded = false, this.sent = const {}, this.dismissed = const {}});

  final bool loaded;
  final Set<String> sent;
  final Set<String> dismissed;

  bool hasSent(String date, int to, CheerKind kind) => sent.contains(_cheerKey(date, to, kind));

  bool isDismissed(String date, Cheer cheer) => dismissed.contains(_dismissKey(date, cheer));

  CheerMemoryState copyWith({Set<String>? sent, Set<String>? dismissed, bool? loaded}) =>
      CheerMemoryState(
        loaded: loaded ?? this.loaded,
        sent: sent ?? this.sent,
        dismissed: dismissed ?? this.dismissed,
      );
}

class CheerMemory extends Notifier<CheerMemoryState> {
  @override
  CheerMemoryState build() {
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    unawaited(_load());
    return const CheerMemoryState();
  }

  Future<void> _load() async {
    final sent = await TogetherPrefs.cheersSent();
    final dismissed = await TogetherPrefs.cheersDismissed();
    // Anything marked while the read was in flight must survive it.
    state = state.copyWith(
      loaded: true,
      sent: {...sent, ...state.sent},
      dismissed: {...dismissed, ...state.dismissed},
    );
  }

  /// Marks [kind] as sent at once and sends it; a failure takes the mark back and rethrows so
  /// the sheet can say so. A repeat from another phone is harmless, the server answers 200.
  Future<void> send({required int to, required CheerKind kind, required String date}) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final key = _cheerKey(date, to, kind);
    state = state.copyWith(sent: {...state.sent, key});
    try {
      await client.sendCheer(to: to, kind: kind);
    } on Object {
      state = state.copyWith(sent: {...state.sent}..remove(key));
      rethrow;
    }
    unawaited(TogetherPrefs.setCheersSent(_pruned(state.sent, date)));
  }

  Future<void> dismiss(String date, List<Cheer> cheers) async {
    final keys = {for (final c in cheers) _dismissKey(date, c)};
    final next = _pruned({...state.dismissed, ...keys}, date);
    state = state.copyWith(dismissed: next);
    await TogetherPrefs.setCheersDismissed(next);
  }

  static Set<String> _pruned(Set<String> keys, String date) => {
    for (final k in keys)
      if (k.startsWith('$date|')) k,
  };
}

final cheerMemoryProvider = NotifierProvider<CheerMemory, CheerMemoryState>(CheerMemory.new);

/// The shared wishlist, the claimed history, the gem bank and the price helper. Not cached: the
/// Us screen draws the focus reward from the board, and the rest simply stays hidden until this
/// loads.
class RewardsNotifier extends AsyncNotifier<RewardList> {
  @override
  Future<RewardList> build() async {
    final client = ref.watch(apiClientProvider);
    if (client == null) return const RewardList();
    return client.rewards();
  }

  Future<void> refresh() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      state = AsyncData(await client.rewards());
    } on ApiException catch (e) {
      debugPrint('[NEWME] rewards refresh failed: $e');
    }
  }

  ApiClient _client() => ref.read(apiClientProvider) ?? (throw StateError('Not signed in'));

  /// Runs one change and reloads the wishlist and the board, also when it was refused, because a
  /// refusal means the other phone changed the reward first. Throws [ApiException].
  Future<void> _change(Future<Object?> Function(ApiClient client) call) async {
    final client = _client();
    try {
      await call(client);
    } on ApiException {
      await _reload();
      rethrow;
    }
    await _reload();
  }

  /// Proposes a reward; the partner approves it first unless I am alone on the server.
  Future<void> propose({required String name, required int price}) =>
      _change((c) => c.createReward(name: name, price: price));

  /// Renames a reward or changes its price. A new price on an approved reward is proposed again.
  Future<void> edit(int id, {String? name, int? price}) =>
      _change((c) => c.patchReward(id, name: name, price: price));

  Future<void> withdraw(int id) => _change((c) => c.withdrawReward(id));

  Future<void> answer(int id, {required bool approve}) =>
      _change((c) => c.answerReward(id, approve: approve));

  /// Drops an approved reward from the wishlist.
  Future<void> cancel(int id) => _change((c) => c.cancelReward(id));

  /// Makes an approved reward the bar on Us.
  Future<void> setFocus(int id) => _change((c) => c.focusReward(id));

  /// Spends the price from the bank, which moves the reward into the history.
  Future<void> claim(int id) => _change((c) => c.claimReward(id));

  Future<void> _reload() async {
    await Future.wait([ref.read(boardProvider.notifier).refresh(), refresh()]);
  }
}

final rewardsProvider = AsyncNotifierProvider<RewardsNotifier, RewardList>(RewardsNotifier.new);

/// Flips one push switch. The switch moves at once through [MeNotifier.replace]; the server's
/// answer replaces it, and a failure puts the old value back before rethrowing.
Future<void> setNotificationPref(WidgetRef ref, NotificationPatch patch) async {
  final notifier = ref.read(meProvider.notifier);
  final before = ref.read(meProvider).value?.data;
  if (before == null) return;
  final p = before.notifications;
  await notifier.replace(
    before.copyWith(
      notifications: NotificationPrefs(
        partnerDone: patch.partnerDone ?? p.partnerDone,
        cheers: patch.cheers ?? p.cheers,
        challenge: patch.challenge ?? p.challenge,
        reward: patch.reward ?? p.reward,
        behindPace: patch.behindPace ?? p.behindPace,
        closeToDone: patch.closeToDone ?? p.closeToDone,
        windDown: patch.windDown ?? p.windDown,
        morningPlan: patch.morningPlan ?? p.morningPlan,
        weeklyRecap: patch.weeklyRecap ?? p.weeklyRecap,
        milestones: patch.milestones ?? p.milestones,
        lookback: patch.lookback ?? p.lookback,
      ),
    ),
  );
  try {
    await notifier.save(MePatch(notifications: patch));
  } on Object {
    await notifier.replace(before);
    rethrow;
  }
}
