import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/health_sync.dart';
import '../../state/session.dart';
import '../../state/timezone.dart';
import '../../theme/accent.dart';

/// The server a fresh install probes before the user types anything.
const String kDefaultServer = String.fromEnvironment(
  'NEWME_SERVER',
  defaultValue: 'https://new-me.npc-server.top',
);

enum OnboardingStep { probing, serverFailed, firstJoin, code, choose, profile, health }

enum ProbeFailure { unreachable, wrongAddress, updateRequired }

const _kUnreachableCopy = 'Cannot reach the server. Check your connection or the address.';
const _kWrongAddressCopy = 'That address does not look like a New Me server.';
const _kBadCodeCopy = 'That code did not work. Ask for a fresh one.';
const _kUpdateCopy = 'This version of New Me is too old for the server. Update it from TestFlight.';

extension ProbeFailureCopy on ProbeFailure {
  String get message => switch (this) {
    ProbeFailure.unreachable => _kUnreachableCopy,
    ProbeFailure.wrongAddress => _kWrongAddressCopy,
    ProbeFailure.updateRequired => _kUpdateCopy,
  };
}

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.probing,
    this.started = false,
    this.serverUrl = kDefaultServer,
    this.showServerField = false,
    this.info,
    this.failure,
    this.code = '',
    this.invite,
    this.color = 'green',
    this.error,
    this.busy = false,
    this.signedOut = false,
  });

  final OnboardingStep step;
  final bool started;
  final String serverUrl;
  final bool showServerField;
  final ServerInfo? info;
  final ProbeFailure? failure;

  /// The code that passed /invites/check; sent again with the join.
  final String code;
  final InviteCheck? invite;
  final String color;

  /// An inline message for the field the user just submitted.
  final String? error;
  final bool busy;

  /// True when a forced sign-out brought the user here.
  final bool signedOut;

  Set<String> get takenColors => {for (final u in invite?.users ?? const <UserSummary>[]) u.color};

  OnboardingState copyWith({
    OnboardingStep? step,
    bool? started,
    String? serverUrl,
    bool? showServerField,
    ServerInfo? info,
    ProbeFailure? failure,
    bool clearFailure = false,
    String? code,
    InviteCheck? invite,
    String? color,
    String? error,
    bool clearError = false,
    bool? busy,
  }) => OnboardingState(
    step: step ?? this.step,
    started: started ?? this.started,
    serverUrl: serverUrl ?? this.serverUrl,
    showServerField: showServerField ?? this.showServerField,
    info: info ?? this.info,
    failure: clearFailure ? null : (failure ?? this.failure),
    code: code ?? this.code,
    invite: invite ?? this.invite,
    color: color ?? this.color,
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
    signedOut: signedOut,
  );
}

/// Turns what a user types into a base URL: https by default, no trailing slash.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return kDefaultServer;
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// True when [have] is older than [need]; both are dotted numeric versions.
bool isVersionBelow(String have, String need) {
  if (need.isEmpty) return false;
  final a = have.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final b = need.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  ApiClient _client() => ref.read(apiClientFactoryProvider)(baseUrl: state.serverUrl);

  /// Probes the remembered or default server without asking the user anything.
  Future<void> start() async {
    if (state.started) return;
    final signedOutFrom = ref.read(sessionProvider).signedOutFrom;
    state = OnboardingState(
      started: true,
      serverUrl: signedOutFrom ?? state.serverUrl,
      signedOut: signedOutFrom != null,
    );
    await _probe();
  }

  Future<void> connectTo(String input) async {
    state = state.copyWith(serverUrl: normalizeServerUrl(input));
    await _probe();
  }

  void changeServer() => state = state.copyWith(showServerField: true);

  Future<void> _probe() async {
    state = state.copyWith(step: OnboardingStep.probing, clearFailure: true, clearError: true);
    try {
      final info = await _client().serverInfo();
      if (isVersionBelow(kClientVersion, info.minClientVersion)) {
        return _failProbe(ProbeFailure.updateRequired);
      }
      state = state.copyWith(
        info: info,
        showServerField: false,
        step: info.initialized ? OnboardingStep.code : OnboardingStep.firstJoin,
      );
    } on ApiException catch (e) {
      _failProbe(switch (e.kind) {
        ApiErrorKind.wrongServer => ProbeFailure.wrongAddress,
        ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => ProbeFailure.updateRequired,
        _ => ProbeFailure.unreachable,
      });
    }
  }

  void _failProbe(ProbeFailure failure) => state = state.copyWith(
    step: OnboardingStep.serverFailed,
    failure: failure,
    showServerField: true,
  );

  Future<void> submitCode(String raw) async {
    final code = raw.trim();
    state = state.copyWith(busy: true, clearError: true);
    try {
      final invite = await _client().checkInvite(code);
      if (!invite.valid) {
        state = state.copyWith(busy: false, error: _kBadCodeCopy);
        return;
      }
      state = state.copyWith(
        busy: false,
        code: code,
        invite: invite,
        step: OnboardingStep.choose,
        color: _firstFree(invite.users.map((u) => u.color).toSet()),
      );
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _codeError(e));
    }
  }

  String _codeError(ApiException e) => switch (e.kind) {
    ApiErrorKind.offline => _kUnreachableCopy,
    ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => _kUpdateCopy,
    _ when e.statusCode == 429 => 'Too many tries. Wait a few minutes and try again.',
    _ => _kBadCodeCopy,
  };

  String _firstFree(Set<String> taken) => kAccentPresets
      .firstWhere((p) => !taken.contains(p.id), orElse: () => kAccentPresets.first)
      .id;

  void chooseNew() {
    state = state.copyWith(step: OnboardingStep.profile, clearError: true);
  }

  void back() {
    switch (state.step) {
      case OnboardingStep.profile:
        state = state.copyWith(step: OnboardingStep.choose, clearError: true);
      case OnboardingStep.choose:
        state = state.copyWith(step: OnboardingStep.code, clearError: true);
      default:
        break;
    }
  }

  void setColor(String id) => state = state.copyWith(color: id);

  Future<void> repair(UserSummary user) async {
    await _join(JoinRequest.repair(code: state.code, userId: user.id));
  }

  Future<void> createProfile(String name) async {
    // The server needs a zone to place days; UTC until the device reports one the user can fix.
    final timezone = await ref.read(deviceTimezoneProvider)() ?? 'UTC';
    final trimmed = name.trim();
    final request = (state.info?.initialized ?? true)
        ? JoinRequest.member(
            code: state.code,
            name: trimmed,
            color: state.color,
            timezone: timezone,
          )
        : JoinRequest.first(name: trimmed, color: state.color, timezone: timezone);
    await _join(request);
  }

  Future<void> _join(JoinRequest request) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _client().join(request);
      // The gate must keep onboarding on screen for the Health step once the session exists.
      state = state.copyWith(busy: false, step: OnboardingStep.health, color: result.user.color);
      await ref
          .read(sessionProvider.notifier)
          .signIn(
            Session(
              baseUrl: state.serverUrl,
              token: result.token,
              userId: result.user.id,
              userName: result.user.name,
              color: result.user.color,
            ),
          );
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _joinError(e));
    }
  }

  String _joinError(ApiException e) => switch (e.kind) {
    ApiErrorKind.offline => _kUnreachableCopy,
    ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => _kUpdateCopy,
    _ when e.statusCode == 429 => 'Too many tries. Wait a few minutes and try again.',
    _ => e.message,
  };

  Future<void> connectHealth() async {
    state = state.copyWith(busy: true);
    try {
      await ref.read(healthSyncProvider.notifier).connect();
    } finally {
      finish();
    }
  }

  /// Hands over to the app. Resets for the next time onboarding is needed.
  void finish() => state = const OnboardingState();
}

final onboardingProvider = NotifierProvider<OnboardingController, OnboardingState>(
  OnboardingController.new,
);
