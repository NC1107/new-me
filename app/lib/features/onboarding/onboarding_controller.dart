import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../reminders/reminder_plan.dart';
import '../../state/health_sync.dart';
import '../../state/reminders.dart';
import '../../state/session.dart';
import '../../state/timezone.dart';
import '../../theme/accent.dart';
import '../setup/about_you.dart';
import 'goal_catalog.dart';
import 'onboarding_store.dart';
import '../../state/me.dart';
import '../../state/units.dart';

/// The server a fresh install probes before the user types anything.
const String kDefaultServer = String.fromEnvironment(
  'NEWME_SERVER',
  defaultValue: 'https://new-me.npc-server.top',
);

enum OnboardingStep {
  probing,
  serverFailed,
  welcome,
  code,
  choose,
  who,
  name,
  color,
  units,
  health,
  body,
  weightGoal,
  schedule,
  focus,
  targets,
  reminders,
  done,
}

/// Which way through the flow this person is going.
enum OnboardingPath { first, invitedNew, returning }

enum ProbeFailure { unreachable, wrongAddress, updateRequired }

const _kUnreachableCopy = 'New Me cannot be reached right now.';
const _kWrongAddressCopy = 'That address does not look like a New Me server.';
const _kBadCodeCopy = 'That code did not work. Ask for a fresh one.';
const _kUpdateCopy = 'This version of New Me is too old. Update it from TestFlight.';
const _kNetworkCopy = 'No connection. Check your network and try again.';

extension ProbeFailureCopy on ProbeFailure {
  String get message => switch (this) {
    ProbeFailure.unreachable => _kUnreachableCopy,
    ProbeFailure.wrongAddress => _kWrongAddressCopy,
    ProbeFailure.updateRequired => _kUpdateCopy,
  };
}

/// The "About you" screens of onboarding: the body measurements, then the weight goal.
const kAboutScreens = 2;

const kMaxNameLength = 40;

/// The day starts this long after waking unless the person says otherwise.
const kDefaultStartOffset = 10;
const kInviteCodeLength = 16;

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.probing,
    this.goalIndex = 0,
    this.path,
    this.started = false,
    this.loaded = false,
    this.pending = false,
    this.serverUrl = kDefaultServer,
    this.info,
    this.failure,
    this.code = '',
    this.invite,
    this.name = '',
    this.color = 'green',
    this.selectedUserId,
    this.focuses = const [],
    this.goals = const {},
    this.drafts = const {},
    this.kcal,
    this.foodAnswered = false,
    this.planSaved = false,
    this.reminderMinutes = kDefaultReminderMinutes,
    this.wakeMinutes = kDefaultWake,
    this.bedMinutes = kDefaultBed,
    this.scheduleAnswered = false,
    this.startOffsetMin = kDefaultStartOffset,
    this.units,
    this.unitsAnswered = false,
    this.aboutDone = 0,
    this.displayName = '',
    this.error,
    this.errorTick = 0,
    this.busy = false,
    this.signedOut = false,
    this.forward = true,
  });

  final OnboardingStep step;

  /// Which daily goal screen, while [step] is goals.
  final int goalIndex;
  final OnboardingPath? path;
  final bool started;

  /// True once saved progress has been read, so the app knows whether to resume.
  final bool loaded;

  /// True from the moment the profile exists until the done screen is dismissed. While it is
  /// set the app stays in onboarding even though there is a session.
  final bool pending;
  final String serverUrl;
  final ServerInfo? info;
  final ProbeFailure? failure;

  /// The code that passed /invites/check; sent again with the join.
  final String code;
  final InviteCheck? invite;
  final String name;
  final String color;
  final int? selectedUserId;

  /// Chosen focus ids in catalog order.
  final List<String> focuses;

  /// Goals the person has confirmed, by quest key.
  final Map<String, int> goals;

  /// The preset currently highlighted on a goal screen, before Continue.
  final Map<String, int> drafts;
  final int? kcal;
  final bool foodAnswered;
  final bool planSaved;

  /// The evening reminder time highlighted on its step, in minutes after midnight.
  final int reminderMinutes;

  /// The wake and bed times highlighted on the schedule step, in minutes after midnight.
  final int wakeMinutes;
  final int bedMinutes;
  final bool scheduleAnswered;

  /// How long after waking the day starts, which is when its first notification comes.
  final int startOffsetMin;

  /// The units chosen on their step, or null before it.
  final Units? units;
  final bool unitsAnswered;

  /// How many of the [kAboutScreens] "About you" screens were passed.
  final int aboutDone;

  /// The name to greet on the done screen.
  final String displayName;

  /// An inline message for the field the user just submitted.
  final String? error;

  /// Bumps on every rejected submit so the boxes shake again for the same message.
  final int errorTick;
  final bool busy;

  /// True when a forced sign-out brought the user here.
  final bool signedOut;

  /// The direction of the last move, for the page transition.
  final bool forward;

  Set<String> get takenColors => {for (final u in invite?.users ?? const <UserSummary>[]) u.color};

  /// The quests the chosen focuses turn on, in catalog order.
  List<String> get questKeys => [
    for (final f in kFocuses)
      if (focuses.contains(f.id)) ...f.questKeys,
  ];

  bool get wantsFood => focuses.contains(kEatFocus);

  /// Whether the step is part of the profile set up after joining, which Back may return to.
  static const afterJoin = {
    OnboardingStep.units,
    OnboardingStep.health,
    OnboardingStep.body,
    OnboardingStep.weightGoal,
    OnboardingStep.schedule,
    OnboardingStep.focus,
    OnboardingStep.targets,
    OnboardingStep.reminders,
  };

  bool get hasChoose => invite != null && invite!.canJoinNew && invite!.users.isNotEmpty;

  /// The screens this person will walk through, as (step, goal index) pairs.
  List<(OnboardingStep, int)> get flow {
    const welcome = (OnboardingStep.welcome, 0);
    const code = (OnboardingStep.code, 0);
    const choose = (OnboardingStep.choose, 0);
    // What people know comes first: units, then Health (which can fill in height and weight),
    // then the body and goal, and only then the daily goals worked out from them.
    const profile = [
      (OnboardingStep.name, 0),
      (OnboardingStep.color, 0),
      (OnboardingStep.units, 0),
      (OnboardingStep.health, 0),
      (OnboardingStep.body, 0),
      (OnboardingStep.weightGoal, 0),
      (OnboardingStep.schedule, 0),
      (OnboardingStep.focus, 0),
      (OnboardingStep.targets, 0),
      (OnboardingStep.reminders, 0),
      (OnboardingStep.done, 0),
    ];
    return switch (path) {
      null => [welcome, code, if (hasChoose) choose],
      OnboardingPath.first => [welcome, ...profile],
      OnboardingPath.invitedNew => [welcome, code, if (hasChoose) choose, ...profile],
      OnboardingPath.returning => [
        welcome,
        code,
        if (hasChoose) choose,
        (OnboardingStep.who, 0),
        (OnboardingStep.health, 0),
        (OnboardingStep.reminders, 0),
        (OnboardingStep.done, 0),
      ],
    };
  }

  int get _flowIndex => flow.indexOf((step, 0));

  /// 0 to 1 across the whole flow.
  double get progress {
    final f = flow;
    final i = _flowIndex;
    if (i < 0) return 0;
    if (path == null) return i * 0.05;
    return i / (f.length - 1);
  }

  bool get canGoBack {
    final f = flow;
    final i = _flowIndex;
    if (i <= 0 || busy || step == OnboardingStep.done) return false;
    final previous = f[i - 1].$1;
    return !pending || afterJoin.contains(previous);
  }

  OnboardingState copyWith({
    OnboardingStep? step,
    int? goalIndex,
    OnboardingPath? path,
    bool? started,
    bool? loaded,
    bool? pending,
    String? serverUrl,
    ServerInfo? info,
    ProbeFailure? failure,
    bool clearFailure = false,
    String? code,
    InviteCheck? invite,
    String? name,
    String? color,
    int? selectedUserId,
    List<String>? focuses,
    Map<String, int>? goals,
    Map<String, int>? drafts,
    int? kcal,
    bool clearKcal = false,
    bool? foodAnswered,
    bool? planSaved,
    int? reminderMinutes,
    int? wakeMinutes,
    int? bedMinutes,
    bool? scheduleAnswered,
    int? startOffsetMin,
    Units? units,
    bool? unitsAnswered,
    int? aboutDone,
    String? displayName,
    String? error,
    bool clearError = false,
    bool failSubmit = false,
    bool? busy,
    bool? forward,
  }) => OnboardingState(
    step: step ?? this.step,
    goalIndex: goalIndex ?? this.goalIndex,
    path: path ?? this.path,
    started: started ?? this.started,
    loaded: loaded ?? this.loaded,
    pending: pending ?? this.pending,
    serverUrl: serverUrl ?? this.serverUrl,
    info: info ?? this.info,
    failure: clearFailure ? null : (failure ?? this.failure),
    code: code ?? this.code,
    invite: invite ?? this.invite,
    name: name ?? this.name,
    color: color ?? this.color,
    selectedUserId: selectedUserId ?? this.selectedUserId,
    focuses: focuses ?? this.focuses,
    goals: goals ?? this.goals,
    drafts: drafts ?? this.drafts,
    kcal: clearKcal ? null : (kcal ?? this.kcal),
    foodAnswered: foodAnswered ?? this.foodAnswered,
    planSaved: planSaved ?? this.planSaved,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    wakeMinutes: wakeMinutes ?? this.wakeMinutes,
    bedMinutes: bedMinutes ?? this.bedMinutes,
    scheduleAnswered: scheduleAnswered ?? this.scheduleAnswered,
    startOffsetMin: startOffsetMin ?? this.startOffsetMin,
    units: units ?? this.units,
    unitsAnswered: unitsAnswered ?? this.unitsAnswered,
    aboutDone: aboutDone ?? this.aboutDone,
    displayName: displayName ?? this.displayName,
    error: clearError ? null : (error ?? this.error),
    errorTick: failSubmit ? errorTick + 1 : errorTick,
    busy: busy ?? this.busy,
    signedOut: signedOut,
    forward: forward ?? this.forward,
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
  Future<void> _hydrating = Future.value();

  @override
  OnboardingState build() {
    // A forced sign-out mid-flow strands the saved answers; the next start begins afresh.
    ref.listen(sessionProvider.select((s) => s.session?.userId), (prev, next) {
      if (next == null && prev != null && state.pending) {
        unawaited(OnboardingProgress.clear());
        ref.invalidate(aboutYouProvider);
        state = const OnboardingState(loaded: true);
      }
    });
    _hydrating = _hydrate();
    return const OnboardingState();
  }

  Future<void> _hydrate() async {
    final saved = await OnboardingProgress.load();
    if (saved == null) {
      state = state.copyWith(loaded: true);
      return;
    }
    final base = state.copyWith(
      loaded: true,
      pending: true,
      path: saved.returning ? OnboardingPath.returning : OnboardingPath.invitedNew,
      name: saved.name,
      displayName: saved.name,
      focuses: saved.focuses,
      goals: saved.goals,
      kcal: saved.kcal,
      foodAnswered: saved.foodAnswered,
      planSaved: saved.planSaved,
      scheduleAnswered: saved.scheduleAnswered,
      unitsAnswered: saved.unitsAnswered,
      aboutDone: saved.aboutDone,
    );
    state = _resumeAt(
      base,
      healthAnswered: saved.healthAnswered,
      reminderAnswered: saved.reminderAnswered,
    );
  }

  /// The first screen the saved answers do not cover, in the order of [OnboardingState.flow].
  OnboardingState _resumeAt(
    OnboardingState s, {
    required bool healthAnswered,
    required bool reminderAnswered,
  }) {
    final OnboardingStep step;
    if (s.path == OnboardingPath.returning) {
      step = !healthAnswered
          ? OnboardingStep.health
          : (reminderAnswered ? OnboardingStep.done : OnboardingStep.reminders);
    } else if (!s.unitsAnswered) {
      step = OnboardingStep.units;
    } else if (!healthAnswered) {
      step = OnboardingStep.health;
    } else if (s.aboutDone < 1) {
      step = OnboardingStep.body;
    } else if (s.aboutDone < 2) {
      step = OnboardingStep.weightGoal;
    } else if (!s.scheduleAnswered) {
      step = OnboardingStep.schedule;
    } else if (s.focuses.isEmpty) {
      step = OnboardingStep.focus;
    } else if (!s.planSaved) {
      step = OnboardingStep.targets;
    } else {
      step = reminderAnswered ? OnboardingStep.done : OnboardingStep.reminders;
    }
    return s.copyWith(step: step);
  }

  ApiClient _client() => ref.read(apiClientFactoryProvider)(baseUrl: state.serverUrl);

  Future<void> _persist({bool healthAnswered = false, bool reminderAnswered = false}) =>
      OnboardingProgress(
        returning: state.path == OnboardingPath.returning,
        name: state.displayName,
        focuses: state.focuses,
        goals: state.goals,
        kcal: state.kcal,
        foodAnswered: state.foodAnswered,
        planSaved: state.planSaved,
        scheduleAnswered: state.scheduleAnswered,
        unitsAnswered: state.unitsAnswered,
        aboutDone: state.aboutDone,
        healthAnswered:
            healthAnswered ||
            const {
              OnboardingStep.body,
              OnboardingStep.weightGoal,
              OnboardingStep.schedule,
              OnboardingStep.focus,
              OnboardingStep.targets,
              OnboardingStep.reminders,
              OnboardingStep.done,
            }.contains(state.step),
        reminderAnswered: reminderAnswered || state.step == OnboardingStep.done,
      ).save();

  /// Probes the remembered or default server without asking the user anything.
  Future<void> start() async {
    await _hydrating;
    if (state.started) return;
    final session = ref.read(sessionProvider);
    if (session.session != null && state.pending) {
      state = state.copyWith(
        started: true,
        serverUrl: session.session!.baseUrl,
        color: session.session!.color,
      );
      return;
    }
    if (state.pending) await OnboardingProgress.clear();
    final signedOutFrom = session.signedOutFrom;
    state = OnboardingState(
      started: true,
      loaded: true,
      serverUrl: signedOutFrom ?? state.serverUrl,
      signedOut: signedOutFrom != null,
    );
    await _probe();
  }

  Future<void> connectTo(String input) async {
    state = state.copyWith(serverUrl: normalizeServerUrl(input));
    await _probe();
  }

  Future<void> retryProbe() => _probe();

  Future<void> _probe() async {
    state = state.copyWith(step: OnboardingStep.probing, clearFailure: true, clearError: true);
    try {
      final info = await _client().serverInfo();
      if (isVersionBelow(kClientVersion, info.minClientVersion)) {
        return _failProbe(ProbeFailure.updateRequired);
      }
      state = state.copyWith(
        info: info,
        step: state.signedOut && info.initialized ? OnboardingStep.code : OnboardingStep.welcome,
      );
    } on ApiException catch (e) {
      _failProbe(switch (e.kind) {
        ApiErrorKind.wrongServer => ProbeFailure.wrongAddress,
        ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => ProbeFailure.updateRequired,
        _ => ProbeFailure.unreachable,
      });
    }
  }

  void _failProbe(ProbeFailure failure) =>
      state = state.copyWith(step: OnboardingStep.serverFailed, failure: failure);

  void _go(OnboardingStep step, {int goalIndex = 0, bool forward = true}) {
    state = state.copyWith(step: step, goalIndex: goalIndex, forward: forward, clearError: true);
  }

  void _next() {
    final f = state.flow;
    final i = state._flowIndex;
    if (i < 0 || i + 1 >= f.length) return;
    _go(f[i + 1].$1, goalIndex: f[i + 1].$2);
  }

  void back() {
    if (!state.canGoBack) return;
    final f = state.flow;
    final previous = f[state._flowIndex - 1];
    if (previous.$1 == OnboardingStep.code) {
      state = state.copyWith(code: '');
    }
    _go(previous.$1, goalIndex: previous.$2, forward: false);
  }

  /// GET STARTED. A server that has people already only lets new ones in with a code.
  void begin() {
    if (state.info?.initialized ?? false) {
      _go(OnboardingStep.code);
    } else {
      state = state.copyWith(path: OnboardingPath.first);
      _go(OnboardingStep.name);
    }
  }

  void haveCode() => _go(OnboardingStep.code);

  Future<void> submitCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final invite = await _client().checkInvite(code);
      if (!invite.valid) {
        state = state.copyWith(busy: false, error: _kBadCodeCopy, failSubmit: true);
        return;
      }
      state = state.copyWith(
        busy: false,
        code: code,
        invite: invite,
        color: _firstFree(invite.users.map((u) => u.color).toSet()),
      );
      if (state.hasChoose) {
        _go(OnboardingStep.choose);
      } else if (invite.canJoinNew) {
        chooseNew();
      } else {
        chooseReturning();
      }
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _codeError(e), failSubmit: true);
    }
  }

  String _codeError(ApiException e) => switch (e.kind) {
    ApiErrorKind.offline => _kNetworkCopy,
    ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => _kUpdateCopy,
    _ when e.statusCode == 429 => 'Too many tries. Wait a few minutes and try again.',
    _ => _kBadCodeCopy,
  };

  String _firstFree(Set<String> taken) => kAccentPresets
      .firstWhere((p) => !taken.contains(p.id), orElse: () => kAccentPresets.first)
      .id;

  void chooseNew() {
    state = state.copyWith(path: OnboardingPath.invitedNew);
    _go(OnboardingStep.name);
  }

  void chooseReturning() {
    state = state.copyWith(path: OnboardingPath.returning);
    _go(OnboardingStep.who);
  }

  void setName(String value) => state = state.copyWith(name: value);

  bool get nameReady {
    final trimmed = state.name.trim();
    return trimmed.isNotEmpty && trimmed.length <= kMaxNameLength;
  }

  void continueFromName() {
    if (nameReady) _next();
  }

  void setColor(String id) {
    if (state.takenColors.contains(id)) return;
    state = state.copyWith(color: id, clearError: true);
  }

  void selectPerson(int userId) => state = state.copyWith(selectedUserId: userId);

  Future<void> repairSelected() async {
    final id = state.selectedUserId;
    if (id == null) return;
    await _join(JoinRequest.repair(code: state.code, userId: id));
  }

  /// Creates the profile once name and colour are known.
  Future<void> createProfile() async {
    // The server needs a zone to place days; UTC until the device reports one the user can fix.
    final timezone = await ref.read(deviceTimezoneProvider)() ?? 'UTC';
    final trimmed = state.name.trim();
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
      final returning = request.userId != null;
      // The gate must keep onboarding on screen once the session exists.
      state = state.copyWith(
        busy: false,
        pending: true,
        color: result.user.color,
        displayName: result.user.name,
        step: returning ? OnboardingStep.health : OnboardingStep.units,
        goalIndex: 0,
        forward: true,
      );
      await _persist();
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
    ApiErrorKind.offline => _kNetworkCopy,
    ApiErrorKind.updateRequired || ApiErrorKind.badAppKey => _kUpdateCopy,
    _ when e.statusCode == 429 => 'Too many tries. Wait a few minutes and try again.',
    _ => e.message,
  };

  void chooseUnits(Units units) {
    state = state.copyWith(units: units);
    ref.read(signupUnitsProvider.notifier).choose(units);
  }

  /// Saves the units on the profile so every later screen, and the server's words, follow them.
  Future<void> continueUnits() async {
    final client = ref.read(apiClientProvider);
    if (client == null || state.busy) return;
    final Units units = state.units ?? ref.read(unitsProvider);
    chooseUnits(units);
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref.read(meProvider.notifier).save(MePatch(units: units));
      state = state.copyWith(busy: false, unitsAnswered: true);
      await _persist();
      _next();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _joinError(e));
    }
  }

  /// The chosen start time, as minutes after midnight, becomes the wait after waking.
  void setDayStart(int minutes) {
    final gap = (minutes - state.wakeMinutes) % (24 * 60);
    state = state.copyWith(startOffsetMin: gap > kMaxFirstOffsetMin ? 0 : gap);
  }

  void setWake(int minutes) => state = state.copyWith(wakeMinutes: minutes);

  void setBed(int minutes) => state = state.copyWith(bedMinutes: minutes);

  /// Saves one wake and bed time for workdays and days off alike; Me > Schedule tells them apart.
  Future<void> continueSchedule() async {
    if (state.busy || state.wakeMinutes == state.bedMinutes) return;
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    state = state.copyWith(busy: true, clearError: true);
    final times = DayTimes(wake: state.wakeMinutes, bed: state.bedMinutes);
    try {
      await client.patchMe(
        MePatch(
          schedule: Schedule(
            workday: times,
            dayOff: times,
            firstNotificationOffsetMin: state.startOffsetMin,
          ),
        ),
      );
      state = state.copyWith(busy: false, scheduleAnswered: true);
      await _persist();
      _next();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _joinError(e));
    }
  }

  /// Keeps the server's defaults (7:00 and 23:00, Monday to Friday).
  Future<void> skipSchedule() async {
    state = state.copyWith(scheduleAnswered: true, clearError: true);
    await _persist();
    _next();
  }

  void toggleFocus(String id) {
    final on = state.focuses.contains(id);
    final next = [
      for (final f in kFocuses)
        if (f.id == id ? !on : state.focuses.contains(f.id)) f.id,
    ];
    state = state.copyWith(focuses: next);
  }

  Future<void> continueFocus() async {
    if (state.focuses.isEmpty) return;
    // Goals for a focus that was dropped no longer count.
    final keys = state.questKeys.toSet();
    state = state.copyWith(
      goals: {
        for (final e in state.goals.entries)
          if (keys.contains(e.key)) e.key: e.value,
      },
      planSaved: false,
    );
    await _persist();
    _next();
  }

  void setKcal(int? value) =>
      state = value == null ? state.copyWith(clearKcal: true) : state.copyWith(kcal: value);

  /// Saves the daily goals the targets screen shows, as adjusted.
  Future<void> commitTargets(Map<String, int> goals, {int? kcal}) async {
    state = state.copyWith(
      goals: goals,
      kcal: kcal,
      clearKcal: kcal == null,
      foodAnswered: true,
      planSaved: false,
    );
    await _persist();
    await _commitPlan();
  }

  /// Saves focus, goals and the calorie target with one PATCH /api/me.
  Future<void> _commitPlan() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    state = state.copyWith(busy: true, clearError: true);
    final chosen = state.questKeys.toSet();
    try {
      await client.patchMe(
        MePatch(
          kcalTarget: state.kcal,
          questTemplates: [
            for (final key in kAllQuestKeys)
              if (chosen.contains(key))
                QuestEdit(key: key, enabled: true, target: state.goals[key])
              else
                QuestEdit(key: key, enabled: false),
          ],
        ),
      );
      state = state.copyWith(busy: false, planSaved: true);
      await _persist();
      _next();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: _joinError(e));
    }
  }

  /// Asks for access and moves on as soon as Apple answers; the first sync carries on behind
  /// the next screens instead of holding this one.
  Future<void> connectHealth() async {
    state = state.copyWith(busy: true);
    try {
      await ref.read(healthSyncProvider.notifier).connect(waitForSync: false);
    } finally {
      await _healthDone();
    }
  }

  Future<void> skipHealth() => _healthDone();

  Future<void> _healthDone() async {
    state = state.copyWith(busy: false);
    _next();
    await _persist(healthAnswered: true);
  }

  /// Moves past an "About you" screen, answered or skipped, remembering how far the person got.
  Future<void> advanceAbout() async {
    final passed = state.step == OnboardingStep.body ? 1 : 2;
    if (passed > state.aboutDone) state = state.copyWith(aboutDone: passed);
    _next();
    await _persist();
  }

  void setReminderMinutes(int minutes) => state = state.copyWith(reminderMinutes: minutes);

  Future<void> allowReminders() async {
    state = state.copyWith(busy: true);
    try {
      await ref.read(remindersProvider.notifier).enable(minutes: state.reminderMinutes);
    } finally {
      await _remindersDone();
    }
  }

  Future<void> skipReminders() async {
    await ref.read(remindersProvider.notifier).disable();
    await _remindersDone();
  }

  Future<void> _remindersDone() async {
    state = state.copyWith(busy: false);
    _go(OnboardingStep.done);
    await _persist(healthAnswered: true, reminderAnswered: true);
  }

  /// Hands over to the app. Resets for the next time onboarding is needed.
  void finish() {
    unawaited(OnboardingProgress.clear());
    ref.invalidate(aboutYouProvider);
    state = const OnboardingState(loaded: true);
  }
}

final onboardingProvider = NotifierProvider<OnboardingController, OnboardingState>(
  OnboardingController.new,
);
