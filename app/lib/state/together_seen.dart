import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'board.dart';
import 'session.dart';
import 'together.dart';
import 'together_prefs.dart';
import 'today.dart';

/// Which finished challenge and reached reward this phone already celebrated, as state so the Us
/// tab badge can follow it.
@immutable
class TogetherSeenState {
  const TogetherSeenState({this.loaded = false, this.challengeEndsOn, this.rewardId});

  final bool loaded;
  final String? challengeEndsOn;
  final int? rewardId;
}

class TogetherSeen extends Notifier<TogetherSeenState> {
  @override
  TogetherSeenState build() {
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    unawaited(_load());
    return const TogetherSeenState();
  }

  Future<void> _load() async {
    final challenge = await TogetherPrefs.celebratedChallenge();
    final reward = await TogetherPrefs.celebratedReward();
    state = TogetherSeenState(
      loaded: true,
      challengeEndsOn: state.challengeEndsOn ?? challenge,
      rewardId: state.rewardId ?? reward,
    );
  }

  Future<void> markChallenge(String endsOn) async {
    state = TogetherSeenState(loaded: true, challengeEndsOn: endsOn, rewardId: state.rewardId);
    await TogetherPrefs.setCelebratedChallenge(endsOn);
  }

  Future<void> markReward(int id) async {
    state = TogetherSeenState(loaded: true, challengeEndsOn: state.challengeEndsOn, rewardId: id);
    await TogetherPrefs.setCelebratedReward(id);
  }
}

final togetherSeenProvider = NotifierProvider<TogetherSeen, TogetherSeenState>(TogetherSeen.new);

/// Whether the Us tab has something new: a cheer not yet dismissed, a challenge that completed or
/// a reward that was reached and has not been celebrated here.
bool usNeedsAttention({
  required List<Cheer> cheers,
  required String cheerDate,
  required CheerMemoryState cheerMemory,
  required Board? board,
  required TogetherSeenState seen,
}) {
  if (cheerMemory.loaded && cheers.any((c) => !cheerMemory.isDismissed(cheerDate, c))) return true;
  if (!seen.loaded || board == null) return false;
  final challenge = board.challenge;
  if (challenge != null && challenge.done && seen.challengeEndsOn != challenge.endsOn) return true;
  final reward = board.reward;
  return reward != null && reward.ready && seen.rewardId != reward.id;
}

final usBadgeProvider = Provider<bool>((ref) {
  final today = ref.watch(todayProvider).value?.data;
  return usNeedsAttention(
    cheers: today?.cheers ?? const [],
    cheerDate: today?.localToday ?? '',
    cheerMemory: ref.watch(cheerMemoryProvider),
    board: ref.watch(boardProvider).value?.data,
    seen: ref.watch(togetherSeenProvider),
  );
});
