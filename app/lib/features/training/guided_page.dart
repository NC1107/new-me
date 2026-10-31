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
import '../../state/training.dart';
import '../../state/yoga.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
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

/// What differs between guided routines: the words around the timer and how the holds are built.
/// Mobility and the yoga flows both run on [GuidedPage].
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
  // One id for the whole session, so a retry after a dropped reply cannot log it twice.
  final _clientOpId = newClientOpId();

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    _audio = ref.read(sessionAudioProvider);
    // Read now so the saved choice has loaded by the time Start is tapped.
    ref.read(guidedSoundProvider);
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

  String _holdPhrase(GuidedHold h) => '${h.exercise.name}, ${h.label}';

  final _voice = const GuidedVoice();
  int _cueIndex = -1;
  Map<int, VoiceLine> _cues = const {};

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
      _cues = _voice.cues(session.holds, session.index);
    }
    final clip = _cues[session.current.seconds - session.holdLeft];
    if (clip != null) _audio.playLines([clip]);
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
        _announce('Go');
      case GuidedEvent.countdown:
        if (loud) _tone((a) => a.tick());
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
    _loggedMinutes = session.minutes;
    setState(() => _stage = _Stage.finished);
    _announce(
      '${_routine.title} done. ${session.minutes} ${session.minutes == 1 ? 'minute' : 'minutes'}',
    );
    unawaited(_log());
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
              type: 'yoga',
              quantity: _loggedMinutes,
              unit: 'minutes',
            ),
          );
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
      builder: (sheet) =>
          _EndSheet(title: _routine.title, worthLogging: worthLogging, minutes: minutes),
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
        _loggedMinutes = minutes;
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
        ),
        _Stage.finished => _Finished(
          routine: _routine,
          minutes: _loggedMinutes,
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
        const SizedBox(height: 8),
        for (final (i, note) in routine.notes.indexed) ...[
          if (i > 0) const SizedBox(height: 4),
          Text(note, style: i == 0 ? AppText.caption : AppText.caption.copyWith(color: kInkMuted)),
        ],
        const SizedBox(height: 16),
        if (list == null)
          const SkeletonBlock(height: 240, radius: kRadiusCard)
        else if (list.isEmpty)
          Text(routine.emptyCopy, style: AppText.body.copyWith(color: kInkSecondary))
        else ...[
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
          Text(routine.footnote, style: AppText.caption.copyWith(color: kInkMuted)),
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
  });

  final GuidedRoutine routine;
  final GuidedController session;
  final GuidedSound sound;
  final VoidCallback onSound;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final hold = session.current;
    final e = hold.exercise;
    final leadIn = session.phase == GuidedPhase.leadIn;
    final accent = context.accentPalette;
    final instant = MediaQuery.disableAnimationsOf(context);
    final paused = session.paused;
    final digits = leadIn ? session.leadLeft : session.holdLeft;
    final status = paused ? 'Paused' : (leadIn ? 'Get ready' : 'seconds left');
    final fraction = leadIn
        ? 1 - session.leadLeft / kHoldLeadInSeconds
        : 1 - session.holdLeft / hold.seconds;
    // The end position is the one to copy; a pose keeps its photos, since cat-cow is a movement.
    final photos = e.yoga ? e.imageUrls : (e.imageUrls.isEmpty ? <String>[] : [e.imageUrls.last]);
    final credits = e.pose?.imageCredits ?? const <ImageCredit>[];
    final inlinePhoto = photos.length == 1;
    // Photos by one person under one license share a single credit line.
    final sharedCredit =
        photos.length > 1 &&
        credits.length > 1 &&
        credits.every((c) => c.label == credits.first.label);
    final roomy = MediaQuery.textScalerOf(context).scale(16) <= 16 * 1.3;
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
            label: paused ? 'Paused' : (leadIn ? 'Get ready' : 'Hold timer running'),
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
                      '$digits',
                      style: AppText.tabular(AppText.display.copyWith(fontSize: 32, height: 1)),
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
        Semantics(header: true, child: Text(e.name, style: AppText.headline)),
        Text(hold.label, style: AppText.label.copyWith(color: kInkSecondary)),
        const SizedBox(height: 2),
        Text('Next: $next', style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );

    return PageScaffold(
      title: routine.title,
      subtitle:
          '${routine.stepNoun[0].toUpperCase()}${routine.stepNoun.substring(1)} '
          '${hold.stepIndex + 1} of ${session.stepCount}',
      footer: _Controls(
        roomy: roomy,
        paused: paused,
        sound: sound,
        canGoBack: session.canGoBack,
        onSound: onSound,
        onPause: onPause,
        onSkip: onSkip,
        onBack: onBack,
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
        if (tall && photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          // The photo is what someone on the mat glances at, so on a tall phone it takes what
          // the screen has to spare past the fixed parts; a short one keeps it beside the name.
          LayoutBuilder(
            builder: (context, box) {
              final height = ((MediaQuery.sizeOf(context).height - 560) * 0.6).clamp(120.0, 190.0);
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

/// Pause in the middle with Previous and Skip beside it and the sound button; at large text sizes
/// the actions wrap under the button instead.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.roomy,
    required this.paused,
    required this.sound,
    required this.canGoBack,
    required this.onSound,
    required this.onPause,
    required this.onSkip,
    required this.onBack,
  });

  final bool roomy;
  final bool paused;
  final GuidedSound sound;
  final bool canGoBack;
  final VoidCallback onSound;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final pause = ChunkyButton(
      label: paused ? 'Resume' : 'Pause',
      icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
      onPressed: onPause,
    );
    final previous = _TextAction(label: 'Previous', onTap: canGoBack ? onBack : null);
    final skip = _TextAction(label: 'Skip', onTap: onSkip);
    final speaker = _SoundButton(sound: sound, onTap: onSound);
    if (roomy) {
      return Row(
        children: [
          speaker,
          previous,
          Expanded(child: pause),
          skip,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pause,
        const SizedBox(height: 4),
        // Wraps rather than overflows when the text is scaled up.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [previous, speaker, skip],
        ),
      ],
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
      (true, true) => (Icons.volume_up_rounded, 'Sounds and voice on'),
      (true, false) => (Icons.volume_down_rounded, 'Sounds on, voice off'),
      _ => (Icons.volume_off_rounded, 'Sounds off'),
    };
    return Semantics(
      button: true,
      label: label,
      hint: 'Double tap to change',
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: context.accentPalette.lip, size: 26),
        ),
      ),
    );
  }
}

/// Ends the session early: a primary action that logs what was done, a secondary that does not,
/// and "Keep going" as the way out, so dismissing the sheet is safe.
class _EndSheet extends StatelessWidget {
  const _EndSheet({required this.title, required this.worthLogging, required this.minutes});

  final String title;
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
                ? 'You\'ve done $minutes $unit. Log ${minutes == 1 ? 'it' : 'them'} to your yoga quest?'
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
    required this.logging,
    required this.error,
    required this.onRetry,
    required this.onDone,
  });

  final GuidedRoutine routine;
  final int minutes;
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
            'your yoga quest.',
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
                  ? 'Logged $minutes $unit to your yoga quest.'
                  : 'Logging $minutes $unit to your yoga quest.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
        ],
      ],
    );
  }
}

/// A plain text action with a 44 point tap target.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        overlayColor: Colors.transparent,
        foregroundColor: context.accentPalette.lip,
        disabledForegroundColor: kInkMuted,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
