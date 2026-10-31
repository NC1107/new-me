import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart' show ApiException;
import '../api/coach_models.dart';
import '../util/errors.dart';
import 'clock.dart';
import 'session.dart';

/// The server accepts at most this many messages, starting and ending with the person.
const kCoachWindow = 20;

/// The longest message the server takes from the person.
const kCoachMaxChars = 1000;

/// What the phone keeps for the day, so reopening the page does not lose the thread.
const _kStoredMessages = 40;

@immutable
class CoachChatState {
  const CoachChatState({this.messages = const [], this.sending = false, this.error});

  final List<ChatMessage> messages;
  final bool sending;

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
      state = CoachChatState(messages: [...state.messages, ChatMessage(ChatRole.assistant, reply)]);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = CoachChatState(messages: state.messages, error: _copy(e));
    }
    unawaited(_persist());
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
