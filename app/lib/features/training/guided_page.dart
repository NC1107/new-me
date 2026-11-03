import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../audio/session_audio.dart';
import '../../audio/voice_line.dart';
import '../../state/guided_sound.dart';
import '../../state/log_actions.dart';
import '../../state/today.dart';
import '../../state/training.dart';
import '../../state/yoga.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/reps_exercises.dart';
import '../../widgets/info_note.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import 'how_to_sheet.dart';
import 'guided_session.dart';
import 'guided_voice.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

enum _Stage { intro, running, finished }

enum _Logging { idle, busy, done, failed, nothing }

enum _EndChoice { keepGoing, discard, log }

/// One part of an intro outline, such as the warm-up, and its exercises.
class GuidedOutlineSection {
  GuidedOutlineSection(this.heading, this.rows);

  final String heading;
  final List<GuidedOutlineRow> rows;
}

class GuidedOutlineRow {
  const GuidedOutlineRow(this.name, this.detail);

  final String name;
  final String detail;
}

/// What differs between guided routines: the words around the timer and how the holds are built.
/// Mobility, the yoga flows and calisthenics all run on [GuidedPage].
class GuidedRoutine {
  const GuidedRoutine({
    required this.title,
    required this.stepNoun,
    required this.stepNounPlural,
    required this.activity,
    required this.doneNoun,
    required this.fallbackIntro,
    required this.introFor,
    required this.notes,
    required this.emptyCopy,
    required this.footnote,
    required this.build,
    this.outline,
    this.voice = const GuidedVoice(),
    this.activityType = 'yoga',
    this.loggedTo = 'your yoga quest',
    this.subtitleLead = '',
    this.logsReps = false,
    this.strengthCreditMinutes,
    this.voiceCountdown = false,
  });

  /// "Mobility" or "Yoga 10".
  final String title;

  /// "stretch" or "pose", for "Stretch 3 of 10".
  final String stepNoun;
  final String stepNounPlural;

  /// "stretching" or "yoga", for "Under 30 seconds of stretching".
  final String activity;

  /// "mobility" or "yoga", for "5 minutes of mobility".
  final String doneNoun;
  final String fallbackIntro;
  final String Function(int steps, int minutes) introFor;

  /// Caption lines under the intro: the order is New Me's own, and the research behind the holds.
  final List<String> notes;
  final String emptyCopy;
  final String footnote;
  final List<GuidedHold> Function(ExerciseCatalog catalog) build;

  /// Sections for the intro in place of one numbered list, for a routine with a warm-up,
  /// rounds and a cool-down.
  final List<GuidedOutlineSection> Function(List<GuidedHold> holds)? outline;

  /// The script that narrates the session.
  final GuidedVoice voice;

  /// The activity type the finished minutes are logged as, and where they count, for "Logged 20
  /// minutes to ...".
  final String activityType;
  final String loggedTo;

  /// Before "exercise 3 of 30" in the app bar, such as the level.
  final String subtitleLead;

  /// Whether finished rep steps are logged toward the daily reps quest.
  final bool logsReps;

  /// The minutes from which a finished session counts as the day's strength session, if it can.
  final int? strengthCreditMinutes;

  /// Whether the voice counts the last seconds of a hold, which replaces the tick tones.
  final bool voiceCountdown;
}

/// A guided routine: a timer with a lead-in before each hold, the photos and steps of the
/// current stretch or pose, and the minutes logged to the yoga quest when it ends.
class GuidedPage extends ConsumerStatefulWidget {
  const GuidedPage({super.key, required this.routine, this.now = DateTime.now});

  final GuidedRoutine routine;

  /// The wall clock, read only to measure time spent in the background.
  final DateTime Function() now;

  @override
  ConsumerState<GuidedPage> createState() => _GuidedPageState();
}

class _GuidedPageState extends ConsumerState<GuidedPage> {
  GuidedRoutine get _routine => widget.routine;
  GuidedController? _session;
  // Read once, because dispose cannot use ref.
  late final ScreenAwake _awake;
  bool _screenHeld = false;
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;
  _Stage _stage = _Stage.intro;
  _Logging _logging = _Logging.idle;
  String? _error;
  int _loggedMinutes = 0;
  // Reps finished by exercise name, shown on the last screen; those of the daily-reps exercise
  // are logged too, each under its own id so a retry cannot count them twice.
  Map<String, int> _repsByKey = const {};
  Map<String, String> _names = const {};
  // Read when the session ends, since logging the minutes refreshes Today.
  String? _questExercise;
  final Map<String, String> _repsOpIds = {};
  // One id for the whole session, so a retry after a dropped reply cannot log it twice.
  final _clientOpId = newClientOpId();

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    _audio = ref.read(sessionAudioProvider);
    // Read now so the saved choice has loaded by the time Start is tapped.
    ref.read(guidedSoundProvider);
    // Needed at the end to log reps toward the quest's own exercise.
    if (_routine.logsReps) ref.read(todayProvider);
    _lifecycle = AppLifecycleListener(onHide: _hide, onShow: _show);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _releaseScreen();
    _audio.stopSpeaking();
    _lifecycle.dispose();
    _session?.dispose();
    super.dispose();
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
  }

  String _holdPhrase(GuidedHold h) =>
      h.isRest ? 'Rest. Next, ${h.exercise.name}' : '${h.exercise.name}, ${h.label}';

  GuidedVoice get _voice => _routine.voice;
  int _cueIndex = -1;
  Map<int, List<VoiceLine>> _cues = const {};

  /// How many changes ahead of the current hold are fetched from the server voice.
  static const _prefetchHolds = 3;

  late final SessionAudio _audio;

  /// A tone, unless sounds are off. Ticks and chimes are also fine with VoiceOver on.
  void _tone(void Function(SessionAudio audio) cue) {
    if (ref.read(guidedSoundProvider).sound) cue(_audio);
  }

  /// Voice is off when the person chose it, and with VoiceOver on, which already announces each
  /// change and must not be spoken over twice.
  bool get _voiceOn =>
      ref.read(guidedSoundProvider).voice && !MediaQuery.accessibleNavigationOf(context);

  /// What to say for a moment: the script's lines, or the plain words where the pose has no
  /// script. Either way the audio layer picks the bundled clip, the server voice or the phone's.
  void _narrate(List<VoiceLine> lines, [String? fallback]) {
    if (!_voiceOn) return;
    final spoken = lines.isEmpty && fallback != null ? [VoiceLine(fallback)] : lines;
    if (spoken.isNotEmpty) _audio.playLines(spoken);
  }

  List<VoiceLine> _advanceLines(List<GuidedHold> holds, int index) {
    final lines = _voice.advance(holds, index);
    return lines.isNotEmpty
        ? lines
        : [VoiceLine('Next: ${nextPhrase(holds[index - 1], holds[index])}')];
  }

  /// Asks the server voice for the next few changes now, so they start without a wait.
  void _prefetchAhead(GuidedController session) {
    if (!_voiceOn) return;
    final holds = session.holds;
    final end = math.min(holds.length, session.index + 1 + _prefetchHolds);
    _audio.prefetch([for (var i = session.index + 1; i < end; i++) ..._advanceLines(holds, i)]);
  }

  /// The recorded cue due at this second of the hold, if any.
  void _cueVoice(GuidedController session) {
    if (session.phase != GuidedPhase.hold || !_voiceOn) return;
    if (_cueIndex != session.index) {
      _cueIndex = session.index;
      _cues = _voice.cueLines(session.holds, session.index);
    }
    final lines = _cues[session.holdElapsed];
    if (lines != null) _audio.playLines(lines);
  }

  void _releaseScreen() {
    if (!_screenHeld) return;
    _screenHeld = false;
    unawaited(_awake.disable());
  }

  /// What is coming, for the "Next:" line and the voice: a new pose by name, and the side only
  /// where there is one. The next hold of the same pose is just its label.
  static String nextPhrase(GuidedHold? from, GuidedHold? to) {
    if (to == null) return 'Last one';
    if (to.isRest) return 'Rest';
    if (from != null && from.stepIndex == to.stepIndex) return to.label;
    final side = to.label.startsWith('Left') || to.label.startsWith('Right') ? ', ${to.label}' : '';
    return '${to.exercise.name}$side';
  }

  void _start(List<GuidedHold> holds) {
    final session = GuidedController(holds)..addListener(_changed);
    _session = session;
    _screenHeld = true;
    unawaited(_awake.enable());
    unawaited(_audio.prepare());
    _narrate(_voice.opening(holds), 'Starting with ${nextPhrase(null, session.current)}');
    _prefetchAhead(session);
    _startTicker();
    setState(() => _stage = _Stage.running);
    HapticFeedback.selectionClick();
    _announce(
      '${_routine.title}. ${session.stepCount} ${_routine.stepNounPlural}. '
      'Get ready. ${_holdPhrase(session.current)}. Starting in $kHoldLeadInSeconds seconds',
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _startTicker({Duration firstTick = const Duration(seconds: 1)}) {
    _ticker?.cancel();
    _ticker = Timer(firstTick, () {
      _step(1);
      if (mounted && _stage == _Stage.running) _startTicker();
    });
  }

  // The ticker stops while hidden so that the wall clock replayed on return is the only count.
  void _hide() {
    if (_stage != _Stage.running) return;
    _hiddenAt = widget.now();
    _ticker?.cancel();
  }

  void _show() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    final session = _session;
    if (hiddenAt == null || session == null || _stage != _Stage.running) return;
    final away = widget.now().difference(hiddenAt);
    if (!session.paused) _step(away.inSeconds, quiet: true);
    if (_stage != _Stage.running) return;
    final remainder = Duration(milliseconds: away.inMilliseconds % 1000);
    _startTicker(firstTick: const Duration(seconds: 1) - remainder);
  }

  /// Replays [seconds] of active time. After a stay in the background only the final state is
  /// announced, not every second that went by.
  void _step(int seconds, {bool quiet = false}) {
    final session = _session;
    if (session == null) return;
    GuidedEvent? last;
    for (var i = 0; i < seconds && !session.finished; i++) {
      final event = session.tick();
      if (!quiet) _cueVoice(session);
      if (event == null) continue;
      if (!quiet) _react(event, session);
      last = event;
    }
    if (quiet && last != null) _react(last, session, loud: false);
    if (session.finished) _finish();
  }

  void _react(GuidedEvent event, GuidedController session, {bool loud = true}) {
    switch (event) {
      case GuidedEvent.leadInTick:
        if (loud) HapticFeedback.selectionClick();
      case GuidedEvent.go:
        if (loud) HapticFeedback.mediumImpact();
        _announce(
          session.current.isReps
              ? 'Go. ${session.currentReps} reps. Tap Done when you finish'
              : 'Go',
        );
      case GuidedEvent.countdown:
        if (loud && !(_routine.voiceCountdown && _voiceOn)) _tone((a) => a.tick());
      case GuidedEvent.halfway:
        if (loud) _tone((a) => a.halfway());
      case GuidedEvent.nextHold:
        if (loud) {
          HapticFeedback.lightImpact();
          _tone((a) => a.chime());
          _narrate(_advanceLines(session.holds, session.index));
          _prefetchAhead(session);
        }
        _announce('Next. ${_holdPhrase(session.current)}');
      case GuidedEvent.finished:
        if (loud) _tone((a) => a.chime());
    }
  }

  void _cycleSound() {
    final next = ref.read(guidedSoundProvider).next;
    unawaited(ref.read(guidedSoundProvider.notifier).set(next));
    if (!next.voice) _audio.stopSpeaking();
    HapticFeedback.selectionClick();
    _announce(
      next.voice ? 'Sounds and voice on' : (next.sound ? 'Sounds on, voice off' : 'Sounds off'),
    );
  }

  void _togglePause() {
    final session = _session;
    if (session == null) return;
    if (session.paused) {
      session.resume();
      _announce('Resumed');
    } else {
      session.pause();
      _audio.stopSpeaking();
      _announce('Paused');
    }
    HapticFeedback.selectionClick();
  }

  void _skip() {
    final session = _session!;
    session.skipStep();
    HapticFeedback.selectionClick();
    if (session.finished) {
      _finish();
    } else {
      _announce('Skipped. Next. ${_holdPhrase(session.current)}');
      _narrate(
        _voice.jump(session.holds, session.index),
        'Next: ${nextPhrase(null, session.current)}',
      );
    }
  }

  void _back() {
    final session = _session!;
    session.backStep();
    HapticFeedback.selectionClick();
    _announce('Back. ${_holdPhrase(session.current)}');
    _narrate(
      _voice.jump(session.holds, session.index),
      'Back to ${nextPhrase(null, session.current)}',
    );
  }

  /// The person finished the reps of a rep step, so the session moves on.
  void _done() {
    final session = _session!;
    final event = session.complete();
    if (event == null) return;
    HapticFeedback.mediumImpact();
    _react(event, session);
    if (session.finished) _finish();
  }

  void _adjustReps(int delta) {
    _session!.adjustReps(delta);
    HapticFeedback.selectionClick();
  }

  void _finish() {
    final session = _session!;
    _ticker?.cancel();
    _releaseScreen();
    _audio.stopSpeaking();
    HapticFeedback.heavyImpact();
    if (!session.worthLogging) {
      setState(() {
        _stage = _Stage.finished;
        _logging = _Logging.nothing;
      });
      _announce('${_routine.title} done. Nothing logged');
      return;
    }
    _remember(session);
    setState(() => _stage = _Stage.finished);
    _announce(
      '${_routine.title} done. ${session.minutes} ${session.minutes == 1 ? 'minute' : 'minutes'}',
    );
    unawaited(_log());
  }

  void _remember(GuidedController session) {
    _loggedMinutes = session.minutes;
    _repsByKey = session.repsDone;
    _names = {for (final h in session.holds) h.exercise.key: h.exercise.name};
    _questExercise = _currentQuestExercise();
  }

  /// The exercise today's daily-reps quest counts, or null when that quest is off today.
  String? _currentQuestExercise() {
    final quests = ref.read(todayProvider).value?.data.quests ?? const <Quest>[];
    for (final q in quests) {
      if (q.key == 'pushups') return q.exercise ?? kDefaultRepsExercise;
    }
    return null;
  }

  Future<void> _logReps() async {
    final exercise = _questExercise;
    final reps = exercise == null ? 0 : (_repsByKey[exercise] ?? 0);
    if (reps < 1) return;
    await ref
        .read(logActionsProvider)
        .create(
          ActivityDraft(
            clientOpId: _repsOpIds.putIfAbsent(exercise!, newClientOpId),
            type: 'pushups',
            quantity: math.min(reps, 500),
            unit: 'reps',
            exercise: exercise,
          ),
        );
  }

  Future<void> _log() async {
    if (_logging == _Logging.busy) return;
    setState(() {
      _logging = _Logging.busy;
      _error = null;
    });
    try {
      await ref
          .read(logActionsProvider)
          .create(
            ActivityDraft(
              clientOpId: _clientOpId,
              type: _routine.activityType,
              quantity: _loggedMinutes,
              unit: 'minutes',
            ),
          );
      if (_routine.logsReps) await _logReps();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _logging = _Logging.failed;
          _error = errorCopy(e);
        });
      }
      return;
    }
    if (ref.exists(yogaPlanProvider)) unawaited(ref.read(yogaPlanProvider.notifier).refresh());
    if (mounted) setState(() => _logging = _Logging.done);
  }

  /// Leaving mid-session pauses the clock and asks, because a half session is still worth its
  /// minutes if the person says so.
  Future<void> _leave() async {
    final session = _session;
    if (_stage != _Stage.running || session == null) {
      Navigator.of(context).pop();
      return;
    }
    final wasPaused = session.paused;
    session.pause();
    _audio.stopSpeaking();
    final worthLogging = session.worthLogging;
    final minutes = session.minutes;
    final choice = await showAppSheet<_EndChoice>(
      context,
      builder: (sheet) => _EndSheet(
        title: _routine.title,
        loggedTo: _routine.loggedTo,
        worthLogging: worthLogging,
        minutes: minutes,
      ),
    );
    if (!mounted) return;
    switch (choice ?? _EndChoice.keepGoing) {
      case _EndChoice.keepGoing:
        if (!wasPaused) session.resume();
      case _EndChoice.discard:
        _ticker?.cancel();
        _releaseScreen();
        Navigator.of(context).pop();
      case _EndChoice.log:
        _ticker?.cancel();
        _releaseScreen();
        _remember(session);
        setState(() => _stage = _Stage.finished);
        unawaited(_log());
    }
  }

  Widget _introFor(ExerciseCatalog? catalog) {
    final holds = catalog == null ? null : _routine.build(catalog);
    return _Intro(
      routine: _routine,
      holds: holds,
      onStart: holds == null || holds.isEmpty ? null : () => _start(holds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exercisesProvider).value?.data;
    return PopScope(
      canPop: _stage != _Stage.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: switch (_stage) {
        _Stage.intro => _introFor(catalog),
        _Stage.running => _Running(
          routine: _routine,
          session: _session!,
          sound: ref.watch(guidedSoundProvider),
          onSound: _cycleSound,
          onPause: _togglePause,
          onSkip: _skip,
          onBack: _back,
          onDone: _done,
          onReps: _adjustReps,
        ),
        _Stage.finished => _Finished(
          routine: _routine,
          minutes: _loggedMinutes,
          reps: [for (final e in _repsByKey.entries) (_names[e.key] ?? e.key, e.value)],
          logging: _logging,
          error: _error,
          onRetry: _log,
          onDone: () => Navigator.of(context).pop(),
        ),
      },
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.routine, required this.holds, required this.onStart});

  final GuidedRoutine routine;
  final List<GuidedHold>? holds;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final list = holds;
    final stretches = [
      if (list != null)
        for (final h in list)
          if (h.firstOfStep) h.exercise,
    ];
    final minutes = list == null ? 10 : (guidedTotalSeconds(list) / 60).round();
    return PageScaffold(
      title: routine.title,
      footer: ChunkyButton(label: 'Start', icon: Icons.play_arrow_rounded, onPressed: onStart),
      children: [
        Text(
          list == null || list.isEmpty
              ? routine.fallbackIntro
              : routine.introFor(stretches.length, minutes),
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 16),
        if (list == null)
          const SkeletonBlock(height: 240, radius: kRadiusCard)
        else if (list.isEmpty)
          Text(routine.emptyCopy, style: AppText.body.copyWith(color: kInkSecondary))
        else if (routine.outline != null) ...[
          for (final section in routine.outline!(list)) ...[
            FieldLabel(section.heading),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, row) in section.rows.indexed)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: Row(
                        children: [
                          Expanded(child: Text(row.name, style: AppText.body)),
                          Text(row.detail, style: AppText.caption.copyWith(color: kInkMuted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          InfoNote.label('Sources and safety', paragraphs: [...routine.notes, routine.footnote]),
        ] else ...[
          const FieldLabel('In this order'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, e) in stretches.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}',
                            style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                          ),
                        ),
                        Expanded(child: Text(e.name, style: AppText.body)),
                        if (e.perSide)
                          Text('each side', style: AppText.caption.copyWith(color: kInkMuted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InfoNote.label('Sources and safety', paragraphs: [...routine.notes, routine.footnote]),
        ],
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({
    required this.routine,
    required this.session,
    required this.sound,
    required this.onSound,
    required this.onPause,
    required this.onSkip,
    required this.onBack,
    required this.onDone,
    required this.onReps,
  });

  final GuidedRoutine routine;
  final GuidedController session;
  final GuidedSound sound;
  final VoidCallback onSound;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final void Function(int delta) onReps;

  @override
  Widget build(BuildContext context) {
    final hold = session.current;
    final e = hold.exercise;
    final leadIn = session.phase == GuidedPhase.leadIn;
    final accent = context.accentPalette;
    final instant = MediaQuery.disableAnimationsOf(context);
    final paused = session.paused;
    final counting = hold.isReps && !leadIn;
    final digits = leadIn
        ? '${session.leadLeft}'
        : counting
        ? _clock(session.holdElapsed)
        : '${session.holdLeft}';
    final status = paused
        ? 'Paused'
        : (leadIn
              ? 'Get ready'
              : (counting ? 'your pace' : (hold.isRest ? 'rest left' : 'seconds left')));
    final fraction = leadIn
        ? 1 - session.leadLeft / kHoldLeadInSeconds
        : (counting ? 0.0 : 1 - session.holdLeft / hold.seconds);
    // The end position is the one to copy; a pose keeps its photos, since cat-cow is a movement.
    final photos = e.yoga ? e.imageUrls : (e.imageUrls.isEmpty ? <String>[] : [e.imageUrls.last]);
    final credits = e.pose?.imageCredits ?? const <ImageCredit>[];
    final inlinePhoto = photos.length == 1;
    // Photos by one person under one license share a single credit line.
    final sharedCredit =
        photos.length > 1 &&
        credits.length > 1 &&
        credits.every((c) => c.label == credits.first.label);
    final tall = MediaQuery.sizeOf(context).height >= 740;
    final next = _GuidedPageState.nextPhrase(hold, session.next);

    final timer = SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The digits are decoration for sighted people; the page announces the start and the
          // end of each hold instead of having VoiceOver read every second.
          Semantics(
            container: true,
            label: paused
                ? 'Paused'
                : (leadIn
                      ? 'Get ready'
                      : (hold.isReps ? 'Reps at your own pace' : 'Hold timer running')),
            excludeSemantics: true,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction),
                      duration: instant ? Duration.zero : kMotionDuration,
                      builder: (_, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 5,
                        color: leadIn || paused ? kInkMuted : accent.fill,
                        backgroundColor: kSunken,
                      ),
                    ),
                  ),
                  MediaQuery.withNoTextScaling(
                    child: Text(
                      digits,
                      style: AppText.tabular(
                        AppText.display.copyWith(fontSize: counting ? 22 : 32, height: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: kInkSecondary, fontSize: 12),
          ),
        ],
      ),
    );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(hold.isRest ? 'Rest' : e.name, style: AppText.headline),
        ),
        Text(
          hold.isRest ? 'Up next: ${e.name}' : hold.label,
          style: AppText.label.copyWith(color: kInkSecondary),
        ),
        if (!hold.isRest) ...[
          const SizedBox(height: 2),
          Text('Next: $next', style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );

    return PageScaffold(
      title: routine.title,
      subtitle:
          '${routine.subtitleLead.isEmpty ? '${routine.stepNoun[0].toUpperCase()}${routine.stepNoun.substring(1)}' : '${routine.subtitleLead}${routine.stepNoun}'} '
          '${hold.stepIndex + 1} of ${session.stepCount}',
      actions: [
        if (session.awaitingDone && !paused) _PauseButton(onTap: onPause),
        _SoundButton(sound: sound, onTap: onSound),
      ],
      footer: _Controls(
        stepNoun: routine.stepNoun,
        paused: paused,
        canGoBack: session.canGoBack,
        onPause: onPause,
        onSkip: onSkip,
        onBack: onBack,
        onDone: session.awaitingDone && !paused ? onDone : null,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!tall && inlinePhoto) ...[
              PoseThumb(url: photos.first, name: e.name, credit: credits.firstOrNull, width: 96),
              const SizedBox(width: 12),
            ] else if (!tall && photos.length > 1) ...[
              for (final (i, url) in photos.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                PoseThumb(
                  url: url,
                  name: e.name,
                  credit: sharedCredit ? null : (i < credits.length ? credits[i] : null),
                  openOnTap: i < credits.length ? credits[i] : null,
                  width: 72,
                ),
              ],
              const SizedBox(width: 12),
            ],
            Expanded(child: heading),
            const SizedBox(width: 8),
            timer,
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Session progress',
          value: '${(session.progress * 100).round()} percent',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: session.progress),
              duration: instant ? Duration.zero : kMotionDuration,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                color: accent.fill,
                backgroundColor: kSunken,
              ),
            ),
          ),
        ),
        if (hold.isReps) ...[
          const SizedBox(height: 12),
          _RepPanel(
            reps: session.currentReps,
            name: e.name,
            caption: paused
                ? 'Paused.'
                : (leadIn
                      ? 'Get into position.'
                      : 'At your own pace. Tap the check when you finish.'),
            onMinus: () => onReps(-1),
            onPlus: () => onReps(1),
          ),
        ],
        if (tall && photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          // The photo is what someone on the mat glances at, so on a tall phone it takes what
          // the screen has to spare past the fixed parts; a short one keeps it beside the name.
          LayoutBuilder(
            builder: (context, box) {
              final spare = MediaQuery.sizeOf(context).height - (hold.isReps ? 700 : 560);
              final height = (spare * 0.6).clamp(110.0, 190.0);
              final gap = 8.0;
              final each = inlinePhoto
                  ? (height * 4 / 3).clamp(0.0, box.maxWidth)
                  : ((box.maxWidth - gap * (photos.length - 1)) / photos.length).clamp(
                      0.0,
                      height * 4 / 3,
                    );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, url) in photos.indexed) ...[
                    if (i > 0) SizedBox(width: gap),
                    PoseThumb(
                      url: url,
                      name: e.name,
                      credit: sharedCredit ? null : (i < credits.length ? credits[i] : null),
                      openOnTap: i < credits.length ? credits[i] : null,
                      width: each,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        if (sharedCredit) PhotoCredit(credit: credits.first, plural: true),
        if (e.steps.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final (i, step) in e.steps.indexed) _StepLine(number: i + 1, text: step),
        ],
        for (final cue in e.cues) _CueLine(text: cue),
      ],
    );
  }
}

String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The target of a rep step, large, with a quick plus and minus for a different count. The
/// person sets the pace and taps Done below when they finish.
class _RepPanel extends StatelessWidget {
  const _RepPanel({
    required this.reps,
    required this.name,
    required this.caption,
    required this.onMinus,
    required this.onPlus,
  });

  final int reps;
  final String name;
  final String caption;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Named(
                label: 'One fewer rep',
                onTap: reps > 1 ? onMinus : null,
                child: IconButton(
                  onPressed: reps > 1 ? onMinus : null,
                  tooltip: 'One fewer rep',
                  icon: const Icon(Icons.remove_rounded, size: 28),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    foregroundColor: context.accentPalette.lip,
                    backgroundColor: kSunken,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              Semantics(
                container: true,
                label: '$reps reps of $name',
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MediaQuery.withNoTextScaling(
                      child: Text(
                        '$reps',
                        style: AppText.tabular(AppText.display.copyWith(fontSize: 64, height: 1)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reps == 1 ? 'rep' : 'reps',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                  ],
                ),
              ),
              _Named(
                label: 'One more rep',
                onTap: reps < GuidedController.maxReps ? onPlus : null,
                child: IconButton(
                  onPressed: reps < GuidedController.maxReps ? onPlus : null,
                  tooltip: 'One more rep',
                  icon: const Icon(Icons.add_rounded, size: 28),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    foregroundColor: context.accentPalette.lip,
                    backgroundColor: kSunken,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: kInkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Pause while a rep step is under way, since its centre button is Done.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Named(
      label: 'Pause',
      onTap: onTap,
      child: IconButton(
        onPressed: onTap,
        tooltip: 'Pause',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Icon(Icons.pause_rounded, color: context.accentPalette.lip, size: 26),
      ),
    );
  }
}

/// One numbered step at body size with little air around it, so a whole pose fits on a phone
/// propped on the floor.
class _StepLine extends StatelessWidget {
  const _StepLine({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        container: true,
        label: 'Step $number. $text',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: context.accentPalette.tint, shape: BoxShape.circle),
              child: Text(
                '$number',
                style: AppText.tabular(
                  AppText.label.copyWith(color: kInk, fontSize: 13, height: 1),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppText.body.copyWith(height: 1.25))),
          ],
        ),
      ),
    );
  }
}

class _CueLine extends StatelessWidget {
  const _CueLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: context.accentPalette.lip,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppText.label.copyWith(color: kInkSecondary, height: 1.25)),
          ),
        ],
      ),
    );
  }
}

/// A media-player transport: previous pose, a large play/pause button, next pose. The sound
/// toggle lives in the app bar so it never crowds the transport.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.stepNoun,
    required this.paused,
    required this.canGoBack,
    required this.onPause,
    required this.onSkip,
    required this.onBack,
    this.onDone,
  });

  final String stepNoun;
  final bool paused;
  final bool canGoBack;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  /// Set while a rep step waits for the person: the centre button then says Done.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          label: 'Previous $stepNoun',
          onTap: canGoBack ? onBack : null,
        ),
        const SizedBox(width: 24),
        _TransportButton(
          icon: onDone != null
              ? Icons.check_rounded
              : (paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          label: onDone != null ? 'Done' : (paused ? 'Resume' : 'Pause'),
          onTap: onDone ?? onPause,
          diameter: 58,
          iconSize: 36,
          fill: accent.fill,
          color: accent.onFill,
        ),
        const SizedBox(width: 24),
        _TransportButton(icon: Icons.skip_next_rounded, label: 'Next $stepNoun', onTap: onSkip),
      ],
    );
  }
}

/// A round icon button with a tooltip, which also names it for VoiceOver. Null [onTap] disables it.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.diameter = 48,
    this.iconSize = 28,
    this.fill,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double diameter;
  final double iconSize;
  final Color? fill;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _Named(
      label: label,
      onTap: onTap,
      child: IconButton(
        onPressed: onTap,
        tooltip: label,
        icon: Icon(icon, size: iconSize),
        style: IconButton.styleFrom(
          fixedSize: Size(diameter, diameter),
          minimumSize: Size(diameter, diameter),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          backgroundColor: fill,
          foregroundColor: color ?? context.accentPalette.lip,
          disabledForegroundColor: kInkMuted.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Names an icon button for VoiceOver once, without the tooltip repeating it.
class _Named extends StatelessWidget {
  const _Named({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: child,
    );
  }
}

/// The speaker button: sounds and voice, tones only, or silent, in turn.
class _SoundButton extends StatelessWidget {
  const _SoundButton({required this.sound, required this.onTap});

  final GuidedSound sound;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch ((sound.sound, sound.voice)) {
      (true, true) => (Icons.volume_up_rounded, 'Voice on'),
      (true, false) => (Icons.volume_down_rounded, 'Sounds on, voice off'),
      _ => (Icons.volume_off_rounded, 'Voice off'),
    };
    return _Named(
      label: label,
      onTap: onTap,
      child: IconButton(
        onPressed: onTap,
        tooltip: label,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Icon(icon, color: context.accentPalette.lip, size: 26),
      ),
    );
  }
}

/// Ends the session early: a primary action that logs what was done, a secondary that does not,
/// and "Keep going" as the way out, so dismissing the sheet is safe.
class _EndSheet extends StatelessWidget {
  const _EndSheet({
    required this.title,
    required this.loggedTo,
    required this.worthLogging,
    required this.minutes,
  });

  final String title;
  final String loggedTo;
  final bool worthLogging;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final unit = minutes == 1 ? 'minute' : 'minutes';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        0,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(worthLogging ? 'End $title early?' : 'End $title?', style: AppText.title),
          ),
          const SizedBox(height: 8),
          Text(
            worthLogging
                ? 'You\'ve done $minutes $unit. Log ${minutes == 1 ? 'it' : 'them'} to $loggedTo?'
                : 'You are under $kGuidedMinLogSeconds seconds in, so nothing will be logged.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 16),
          if (worthLogging) ...[
            ChunkyButton(
              label: 'Log $minutes min and end',
              onPressed: () => Navigator.of(context).pop(_EndChoice.log),
            ),
            const SizedBox(height: kCardGap),
            ChunkyButton.secondary(
              label: 'End without logging',
              onPressed: () => Navigator.of(context).pop(_EndChoice.discard),
            ),
          ] else
            ChunkyButton.secondary(
              label: 'End',
              onPressed: () => Navigator.of(context).pop(_EndChoice.discard),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_EndChoice.keepGoing),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
              foregroundColor: context.accentPalette.lip,
            ),
            child: const Text('Keep going', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({
    required this.routine,
    required this.minutes,
    required this.reps,
    required this.logging,
    required this.error,
    required this.onRetry,
    required this.onDone,
  });

  final GuidedRoutine routine;
  final int minutes;

  /// Reps finished per exercise name, for a routine with rep steps.
  final List<(String, int)> reps;
  final _Logging logging;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final unit = minutes == 1 ? 'minute' : 'minutes';
    final failed = logging == _Logging.failed;
    final nothing = logging == _Logging.nothing;
    return PageScaffold(
      title: routine.title,
      footer: failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChunkyButton(label: 'Try again', onPressed: onRetry),
                const SizedBox(height: 10),
                ChunkyButton.secondary(label: 'Done', onPressed: onDone),
              ],
            )
          : ChunkyButton(label: 'Done', busy: logging == _Logging.busy, onPressed: onDone),
      children: [
        if (nothing) ...[
          Semantics(header: true, child: const Text('Nothing logged', style: AppText.display)),
          const SizedBox(height: 8),
          Text(
            'Under $kGuidedMinLogSeconds seconds of ${routine.activity}, so nothing was added to '
            'your ${routine.activityType == 'yoga' ? 'yoga quest' : 'exercise minutes'}.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
        ] else ...[
          Semantics(header: true, child: const Text('Nice work', style: AppText.display)),
          const SizedBox(height: 8),
          Text('$minutes $unit of ${routine.doneNoun}.', style: AppText.headline),
          const SizedBox(height: 8),
          if (failed)
            Text(
              error ?? 'Could not log your session.',
              style: AppText.body.copyWith(color: kDangerText),
            )
          else
            Text(
              logging == _Logging.done
                  ? 'Logged $minutes $unit to ${routine.loggedTo}.'
                  : 'Logging $minutes $unit to ${routine.loggedTo}.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
          if (reps.isNotEmpty && !failed) ...[
            const SizedBox(height: 12),
            for (final (name, count) in reps)
              Text('$name: $count reps', style: AppText.body.copyWith(color: kInkSecondary)),
          ],
          if (routine.strengthCreditMinutes case final credit? when !failed) ...[
            const SizedBox(height: 12),
            Text(
              minutes >= credit
                  ? 'That is $credit minutes or more, so it counts as your strength session.'
                  : 'Under $credit minutes, so it counts as exercise minutes but not as a strength '
                        'session.',
              style: AppText.caption.copyWith(color: kInkMuted),
            ),
          ],
        ],
      ],
    );
  }
}
