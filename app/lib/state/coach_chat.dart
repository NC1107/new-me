import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart' show ApiClient, ApiException;
import '../api/coach_models.dart';
import '../util/errors.dart';
import 'board.dart';
import 'clock.dart';
import 'me.dart';
import 'session.dart';
import 'targets.dart';
import 'today.dart';
import 'training.dart';

/// The server accepts at most this many messages, starting and ending with the person.
const kCoachWindow = 20;

/// The longest message the server takes from the person.
const kCoachMaxChars = 1000;

/// What the phone keeps for the day, so reopening the page does not lose the thread.
const _kStoredMessages = 40;

@immutable
class CoachChatState {
  const CoachChatState({
    this.messages = const [],
    this.sending = false,
    this.error,
    this.working = const {},
    this.cardErrors = const {},
  });

  final List<ChatMessage> messages;
  final bool sending;

  /// Proposal ids with a request in flight, so a card cannot be tapped twice.
  final Set<int> working;

  /// Why a card's last tap failed, by proposal id.
  final Map<int, String> cardErrors;

  CoachChatState copyWith({
    List<ChatMessage>? messages,
    Set<int>? working,
    Map<int, String>? cardErrors,
  }) => CoachChatState(
    messages: messages ?? this.messages,
    sending: sending,
    error: error,
    working: working ?? this.working,
    cardErrors: cardErrors ?? this.cardErrors,
  );

  /// Why the last message got no answer; the message itself stays in [messages] to retry.
  final String? error;
}

/// The coach conversation of this session, kept per person and per local day on the phone. The
/// server keeps nothing, so every send carries the recent thread.
class CoachChat extends Notifier<CoachChatState> {
  @override
  CoachChatState build() {
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    unawaited(_restore());
    return const CoachChatState();
  }

  String? get _key {
    final id = ref.read(sessionProvider).session?.userId;
    return id == null ? null : 'coachChat.v1.$id';
  }

  String get _today {
    final now = ref.read(clockProvider)();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _restore() async {
    final key = _key;
    if (key == null) return;
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || !ref.mounted || state.messages.isNotEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['date'] != _today) return;
      final messages = [
        for (final m in j['messages'] as List<dynamic>)
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ];
      state = CoachChatState(messages: messages);
    } on Object {
      // A stored thread that cannot be read is just a new conversation.
    }
  }

  Future<void> _persist() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (state.messages.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final kept = state.messages.length > _kStoredMessages
        ? state.messages.sublist(state.messages.length - _kStoredMessages)
        : state.messages;
    await prefs.setString(
      key,
      jsonEncode({
        'date': _today,
        'messages': [for (final m in kept) m.toJson()],
      }),
    );
  }

  /// The recent thread as the server wants it: bounded, and starting with the person.
  @visibleForTesting
  static List<ChatMessage> window(List<ChatMessage> all) {
    var recent = all.length > kCoachWindow ? all.sublist(all.length - kCoachWindow) : all;
    while (recent.isNotEmpty && !recent.first.isUser) {
      recent = recent.sublist(1);
    }
    return recent;
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;
    final clipped = trimmed.length > kCoachMaxChars
        ? trimmed.substring(0, kCoachMaxChars)
        : trimmed;
    state = CoachChatState(messages: [...state.messages, ChatMessage(ChatRole.user, clipped)]);
    await _ask();
  }

  /// Asks again after a failure, without repeating the person's message.
  Future<void> retry() async {
    if (state.sending || state.error == null) return;
    await _ask();
  }

  /// Starts a new conversation.
  Future<void> clear() async {
    if (state.sending) return;
    state = const CoachChatState();
    await _persist();
  }

  Future<void> _ask() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    state = CoachChatState(messages: state.messages, sending: true);
    unawaited(_persist());
    try {
      final reply = await client.coachChat(window(state.messages));
      if (!ref.mounted) return;
      state = CoachChatState(
        messages: [
          ...state.messages,
          ChatMessage(ChatRole.assistant, reply.text, actions: reply.actions),
        ],
      );
      if (reply.actions.any((a) => a.type != 'proposal')) unawaited(_reloadFacts());
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = CoachChatState(messages: state.messages, error: _copy(e));
    }
    unawaited(_persist());
  }

  Future<void> applyProposal(int id) => _decide(id, (c) => c.applyCoachProposal(id), reload: true);

  Future<void> dismissProposal(int id) => _decide(id, (c) => c.dismissCoachProposal(id));

  Future<void> undoProposal(int id) => _decide(id, (c) => c.undoCoachProposal(id), reload: true);

  Future<void> _decide(
    int id,
    Future<CoachProposal> Function(ApiClient client) call, {
    bool reload = false,
  }) async {
    final client = ref.read(apiClientProvider);
    if (client == null || state.working.contains(id)) return;
    state = state.copyWith(
      working: {...state.working, id},
      cardErrors: {...state.cardErrors}..remove(id),
    );
    try {
      final next = await call(client);
      if (!ref.mounted) return;
      _replaceProposal(next);
      if (reload) await _reloadSettings();
    } on Object catch (e) {
      if (!ref.mounted) return;
      if (e is ApiException && e.code == 'proposal_expired') {
        _markStatus(id, 'expired');
      }
      state = state.copyWith(cardErrors: {...state.cardErrors, id: _cardCopy(e)});
    }
    if (!ref.mounted) return;
    state = state.copyWith(working: {...state.working}..remove(id));
    unawaited(_persist());
  }

  void _replaceProposal(CoachProposal next) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          m.withActions([
            for (final a in m.actions) a.proposal?.id == next.id ? CoachAction.proposal(next) : a,
          ]),
      ],
    );
  }

  void _markStatus(int id, String status) {
    for (final m in state.messages) {
      for (final a in m.actions) {
        final p = a.proposal;
        if (p != null && p.id == id) {
          _replaceProposal(
            CoachProposal(
              id: p.id,
              kind: p.kind,
              summary: p.summary,
              changes: p.changes,
              why: p.why,
              source: p.source,
              status: status,
              expiresAt: p.expiresAt,
              canUndo: false,
            ),
          );
          return;
        }
      }
    }
  }

  String _cardCopy(Object e) {
    if (e is ApiException && (e.code == 'proposal_expired' || e.code == 'proposal_state')) {
      return e.message;
    }
    return errorCopy(e);
  }

  /// A change made here moves targets, quests and the training plan, so every screen that
  /// shows them is reloaded.
  Future<void> _reloadSettings() async {
    await ref.read(meProvider.notifier).refresh();
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
    if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
    if (ref.exists(targetsProvider)) unawaited(ref.read(targetsProvider.notifier).refresh());
    if (ref.exists(trainingSetupProvider)) ref.invalidate(trainingSetupProvider);
    if (ref.exists(trainingTodayProvider)) {
      unawaited(ref.read(trainingTodayProvider.notifier).refresh());
    }
  }

  Future<void> _reloadFacts() async {
    if (ref.exists(coachFactsProvider)) ref.invalidate(coachFactsProvider);
  }

  /// The coach's own failures arrive as 5xx, which errorCopy would call offline; the server's
  /// sentence says what happened.
  String _copy(Object e) {
    if (e is ApiException && (e.code == 'coach_unavailable' || e.code == 'coach_disabled')) {
      return e.message;
    }
    return errorCopy(e);
  }
}

final coachChatProvider = NotifierProvider<CoachChat, CoachChatState>(CoachChat.new);

/// What the coach has saved about the person, shown under Me.
class CoachFactsNotifier extends AsyncNotifier<List<CoachFact>> {
  @override
  Future<List<CoachFact>> build() async {
    final client = ref.watch(apiClientProvider);
    if (client == null) return const [];
    return client.coachFacts();
  }

  /// Deletes at once and puts the fact back if the server refuses.
  Future<void> remove(CoachFact fact) async {
    final client = ref.read(apiClientProvider);
    final before = state.value ?? const [];
    if (client == null) return;
    state = AsyncData([
      for (final f in before)
        if (f.id != fact.id) f,
    ]);
    try {
      await client.deleteCoachFact(fact.id);
    } on Object {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }
}

final coachFactsProvider = AsyncNotifierProvider<CoachFactsNotifier, List<CoachFact>>(
  CoachFactsNotifier.new,
);
