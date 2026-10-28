import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
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
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import 'how_to_sheet.dart';
import 'guided_session.dart';
import 'set_assist.dart' show kCounterHeight, kHoldLeadInSeconds;

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
    _lifecycle = AppLifecycleListener(onHide: _hide, onShow: _show);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    _session?.dispose();
    super.dispose();
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
  }

  String _holdPhrase(GuidedHold h) => '${h.exercise.name}, ${h.label}';

  void _start(List<GuidedHold> holds) {
    final session = GuidedController(holds)..addListener(_changed);
    _session = session;
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
      case GuidedEvent.nextHold:
        if (loud) HapticFeedback.lightImpact();
        _announce('Next. ${_holdPhrase(session.current)}');
      case GuidedEvent.finished:
        break;
    }
  }

  void _togglePause() {
    final session = _session;
    if (session == null) return;
    if (session.paused) {
      session.resume();
      _announce('Resumed');
    } else {
      session.pause();
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
    }
  }

  void _back() {
    final session = _session!;
    session.backStep();
    HapticFeedback.selectionClick();
    _announce('Back. ${_holdPhrase(session.current)}');
  }

  void _finish() {
    final session = _session!;
    _ticker?.cancel();
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
    final worthLogging = session.worthLogging;
    final minutes = session.minutes;
    final choice = await showDialog<_EndChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kBgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kBorder),
        ),
        title: Text(worthLogging ? 'End ${_routine.title} early?' : 'End ${_routine.title}?'),
        content: Text(
          worthLogging
              ? 'You have done $minutes ${minutes == 1 ? 'minute' : 'minutes'}. '
                    'Log them to your yoga quest?'
              : 'You are under $kGuidedMinLogSeconds seconds in, so nothing will be logged.',
          style: const TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _EndChoice.keepGoing),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _EndChoice.discard),
            style: TextButton.styleFrom(foregroundColor: kFgSecondary),
            child: Text(worthLogging ? 'End without logging' : 'End'),
          ),
          if (worthLogging)
            TextButton(
              onPressed: () => Navigator.pop(context, _EndChoice.log),
              child: Text(
                'Log $minutes min and end',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice ?? _EndChoice.keepGoing) {
      case _EndChoice.keepGoing:
        if (!wasPaused) session.resume();
      case _EndChoice.discard:
        Navigator.of(context).pop();
      case _EndChoice.log:
        _ticker?.cancel();
        _loggedMinutes = minutes;
        setState(() => _stage = _Stage.finished);
        unawaited(_log());
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exercisesProvider).value?.data;
    final holds = catalog == null ? null : _routine.build(catalog);
    return PopScope(
      canPop: _stage != _Stage.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: switch (_stage) {
        _Stage.intro => _Intro(
          routine: _routine,
          holds: holds,
          onStart: holds == null || holds.isEmpty ? null : () => _start(holds),
        ),
        _Stage.running => _Running(
          routine: _routine,
          session: _session!,
          onPause: _togglePause,
          onSkip: _skip,
          onBack: _back,
          onClose: _leave,
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
    required this.onPause,
    required this.onSkip,
    required this.onBack,
    required this.onClose,
  });

  final GuidedRoutine routine;
  final GuidedController session;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hold = session.current;
    final e = hold.exercise;
    final leadIn = session.phase == GuidedPhase.leadIn;
    final accent = context.accentPalette;
    final instant = MediaQuery.disableAnimationsOf(context);
    final paused = session.paused;
    final digits = leadIn ? session.leadLeft : session.holdLeft;
    final caption = paused ? 'Paused' : (leadIn ? 'Get ready' : 'seconds left');
    return PageScaffold(
      title: routine.title,
      subtitle:
          '${routine.stepNoun[0].toUpperCase()}${routine.stepNoun.substring(1)} '
          '${hold.stepIndex + 1} of ${session.stepCount}',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyButton(
            label: paused ? 'Resume' : 'Pause',
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onPressed: onPause,
          ),
          const SizedBox(height: 4),
          // Wraps rather than overflows when the text is scaled up.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TextAction(label: 'Previous', onTap: session.canGoBack ? onBack : null),
              _TextAction(label: 'End', onTap: onClose),
              _TextAction(label: 'Skip', onTap: onSkip),
            ],
          ),
        ],
      ),
      children: [
        Semantics(header: true, child: Text(e.name, style: AppText.title)),
        const SizedBox(height: 2),
        Text(hold.label, style: AppText.label.copyWith(color: kInkSecondary)),
        const SizedBox(height: 12),
        // The digits are decoration for sighted people; the page announces the start and the end
        // of each hold instead of having VoiceOver read every second.
        Semantics(
          container: true,
          label: paused ? 'Paused' : (leadIn ? 'Get ready' : 'Hold timer running'),
          excludeSemantics: true,
          child: Container(
            height: kCounterHeight,
            decoration: BoxDecoration(
              color: leadIn || paused ? kSunken : accent.tint,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(
                color: leadIn || paused ? kBorder : accent.fill,
                width: kBorderWidth,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MediaQuery.withNoTextScaling(
                  child: Text(
                    '$digits',
                    style: AppText.tabular(AppText.display.copyWith(fontSize: 72, height: 1)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(caption, style: AppText.label.copyWith(color: kInkSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                minHeight: 8,
                color: accent.fill,
                backgroundColor: kSunken,
              ),
            ),
          ),
        ),
        if (e.imageUrls.isNotEmpty) ...[const SizedBox(height: 16), HowToPhotosOf(exercise: e)],
        if (e.steps.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Steps', style: AppText.headline),
          const SizedBox(height: 8),
          for (final (i, step) in e.steps.indexed) HowToStep(number: i + 1, text: step),
        ],
        if (e.cues.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final cue in e.cues) HowToCue(text: cue),
        ],
      ],
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
