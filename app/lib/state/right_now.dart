import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'clock.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// Also removed on sign out by LocalPrefs.
const _kDismissed = 'rightNowDismissed';
const _kKeep = 48;

String readinessDismissKey(String date) => 'readiness|$date';

String recapDismissKey(String week) => 'recap|$week';

String lookbackDismissKey(String month) => 'lookback|$month';

/// The setup card stays away for [kSetupDismissDays] days from the day it was dismissed.
String setupDismissKey(String date) => 'setup|$date';

const kSetupDismissDays = 7;

bool setupDismissed(Set<String> dismissed, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (final key in dismissed) {
    if (!key.startsWith('setup|')) continue;
    final day = DateTime.tryParse(key.substring('setup|'.length));
    if (day != null && today.difference(day).inDays < kSetupDismissDays) return true;
  }
  return false;
}

/// A milestone celebration plays once per phone, so its id is the memory.
String milestoneSeenKey(int id) => 'milestone|$id';

/// Which "right now" cards this phone already dismissed. Keys carry their date or week, so an
/// old dismissal never hides a new card.
@immutable
class RightNowMemoryState {
  const RightNowMemoryState({this.loaded = false, this.dismissed = const {}});

  final bool loaded;
  final Set<String> dismissed;

  bool has(String key) => dismissed.contains(key);
}

class RightNowMemory extends Notifier<RightNowMemoryState> {
  @override
  RightNowMemoryState build() {
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    unawaited(_load());
    return const RightNowMemoryState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kDismissed) ?? const [];
    state = RightNowMemoryState(loaded: true, dismissed: {...stored, ...state.dismissed});
  }

  Future<void> dismiss(String key) async {
    final next = {...state.dismissed, key};
    final kept = next.length > _kKeep ? next.skip(next.length - _kKeep).toSet() : next;
    state = RightNowMemoryState(loaded: true, dismissed: kept);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDismissed, kept.toList());
  }
}

final rightNowMemoryProvider = NotifierProvider<RightNowMemory, RightNowMemoryState>(
  RightNowMemory.new,
);

bool isMonday(DateTime now) => now.weekday == DateTime.monday;

/// Sunday from 19:00 (the week is about to end) and all of Monday (it just did).
bool recapWindow(DateTime now) =>
    isMonday(now) || (now.weekday == DateTime.sunday && now.hour >= 19);

/// This week's goal proposals. Only fetched on Mondays: the server freezes a proposal the first
/// time it is shown, and the card is a Monday card.
class GoalProposalsNotifier extends AsyncNotifier<GoalProposals> {
  @override
  Future<GoalProposals> build() async {
    final client = ref.watch(apiClientProvider);
    if (client == null || !isMonday(ref.read(clockProvider)())) return const GoalProposals();
    try {
      return await client.goalProposals();
    } on ApiException catch (e) {
      debugPrint('[NEWME] goal proposals unavailable: $e');
      return const GoalProposals();
    }
  }

  /// The card changes at once; a failure puts the proposal back and rethrows for the card to say so.
  Future<void> accept(String key) => _decide(key, (client) async {
    final me = await client.acceptGoalProposal(key);
    await ref.read(meProvider.notifier).replace(me);
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
  });

  Future<void> dismiss(String key) => _decide(key, (client) => client.dismissGoalProposal(key));

  Future<void> _decide(String key, Future<void> Function(ApiClient client) call) async {
    final client = ref.read(apiClientProvider);
    final before = state.value;
    if (client == null || before == null) return;
    state = AsyncData(before.without(key));
    try {
      await call(client);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}

final goalProposalsProvider = AsyncNotifierProvider<GoalProposalsNotifier, GoalProposals>(
  GoalProposalsNotifier.new,
);

/// The weekly recap; [week] null asks for the server's default week.
final recapProvider = FutureProvider.autoDispose.family<Recap, String?>((ref, week) {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client.recap(week: week);
});
