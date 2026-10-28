import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../state/training.dart';
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
import 'mobility_session.dart';
import 'set_assist.dart' show kCounterHeight, kHoldLeadInSeconds;

enum _Stage { intro, running, finished }

enum _Logging { idle, busy, done, failed }

enum _EndChoice { keepGoing, discard, log }

/// Mobility 10: a guided stretching routine with a timer, the photos and steps of the current
/// stretch, and the minutes logged to the yoga quest when it ends.
class MobilityPage extends ConsumerStatefulWidget {
  const MobilityPage({super.key, this.now = DateTime.now});

  /// The wall clock, read only to measure time spent in the background.
  final DateTime Function() now;

  @override
  ConsumerState<MobilityPage> createState() => _MobilityPageState();
}

class _MobilityPageState extends ConsumerState<MobilityPage> {
  MobilityController? _session;
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

  String _holdPhrase(MobilityHold h) => '${h.exercise.name}, ${h.label}';

  void _start(List<MobilityHold> holds) {
    final session = MobilityController(holds)..addListener(_changed);
    _session = session;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _step(1));
    setState(() => _stage = _Stage.running);
    HapticFeedback.selectionClick();
    _announce(
      'Mobility. ${session.stretchCount} stretches. '
      'Get ready. ${_holdPhrase(session.current)}. Starting in $kHoldLeadInSeconds seconds',
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _hide() => _hiddenAt = widget.now();

  void _show() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    final session = _session;
    if (hiddenAt == null || session == null || session.paused || _stage != _Stage.running) return;
    _step(widget.now().difference(hiddenAt).inSeconds, quiet: true);
  }

  /// Replays [seconds] of active time. After a stay in the background only the final state is
  /// announced, not every second that went by.
  void _step(int seconds, {bool quiet = false}) {
    final session = _session;
    if (session == null) return;
    MobilityEvent? last;
    for (var i = 0; i < seconds && !session.finished; i++) {
      final event = session.tick();
      if (event == null) continue;
      if (!quiet) _react(event, session);
      last = event;
    }
    if (quiet && last != null) _react(last, session, loud: false);
    if (session.finished) _finish();
  }

  void _react(MobilityEvent event, MobilityController session, {bool loud = true}) {
    switch (event) {
      case MobilityEvent.leadInTick:
        if (loud) HapticFeedback.selectionClick();
      case MobilityEvent.go:
        if (loud) HapticFeedback.mediumImpact();
        _announce('Go');
      case MobilityEvent.nextHold:
        if (loud) HapticFeedback.lightImpact();
        _announce('Next. ${_holdPhrase(session.current)}');
      case MobilityEvent.finished:
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
    session.skipStretch();
    HapticFeedback.selectionClick();
    if (session.finished) {
      _finish();
    } else {
      _announce('Skipped. Next. ${_holdPhrase(session.current)}');
    }
  }

  void _back() {
    final session = _session!;
    session.backStretch();
    HapticFeedback.selectionClick();
    _announce('Back. ${_holdPhrase(session.current)}');
  }

  void _finish() {
    final session = _session!;
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    _loggedMinutes = session.minutes;
    setState(() => _stage = _Stage.finished);
    _announce('Mobility done. ${session.minutes} ${session.minutes == 1 ? 'minute' : 'minutes'}');
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
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _logging = _Logging.failed;
          _error = errorCopy(e);
        });
      }
      return;
    }
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
    if (!session.worthLogging) {
      Navigator.of(context).pop();
      return;
    }
    final minutes = session.minutes;
    final choice = await showDialog<_EndChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kBgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kBorder),
        ),
        title: const Text('End Mobility early?'),
        content: Text(
          'You have done $minutes ${minutes == 1 ? 'minute' : 'minutes'}. '
          'Log them to your yoga quest?',
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
            child: const Text('End without logging'),
          ),
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
    final holds = catalog == null ? null : buildMobilityHolds(catalog);
    return PopScope(
      canPop: _stage != _Stage.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: switch (_stage) {
        _Stage.intro => _Intro(
          holds: holds,
          onStart: holds == null || holds.isEmpty ? null : () => _start(holds),
        ),
        _Stage.running => _Running(
          session: _session!,
          onPause: _togglePause,
          onSkip: _skip,
          onBack: _back,
          onClose: _leave,
        ),
        _Stage.finished => _Finished(
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
  const _Intro({required this.holds, required this.onStart});

  final List<MobilityHold>? holds;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final list = holds;
    final stretches = [
      if (list != null)
        for (final h in list)
          if (h.firstOfStretch) h.exercise,
    ];
    final minutes = list == null
        ? 10
        : (list.length * (kMobilityHoldSeconds + kHoldLeadInSeconds) / 60).round();
    return PageScaffold(
      title: 'Mobility 10',
      footer: ChunkyButton(label: 'Start', icon: Icons.play_arrow_rounded, onPressed: onStart),
      children: [
        Text(
          list == null || list.isEmpty
              ? 'Guided stretching, one stretch at a time.'
              : '${stretches.length} stretches, about $minutes minutes. '
                    'A timer runs each hold and moves on by itself.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 8),
        const Text(kMobilityOrderNote, style: AppText.caption),
        const SizedBox(height: 4),
        Text(kMobilityCitation, style: AppText.caption.copyWith(color: kInkMuted)),
        const SizedBox(height: 16),
        if (list == null)
          const SkeletonBlock(height: 240, radius: kRadiusCard)
        else if (list.isEmpty)
          Text(
            'This server has no stretches yet. Update the server to use Mobility.',
            style: AppText.body.copyWith(color: kInkSecondary),
          )
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
          Text(
            'Stretch to a mild pull, never pain. It counts toward your yoga quest when you finish.',
            style: AppText.caption.copyWith(color: kInkMuted),
          ),
        ],
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({
    required this.session,
    required this.onPause,
    required this.onSkip,
    required this.onBack,
    required this.onClose,
  });

  final MobilityController session;
  final VoidCallback onPause;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hold = session.current;
    final e = hold.exercise;
    final leadIn = session.phase == MobilityPhase.leadIn;
    final accent = context.accentPalette;
    final instant = MediaQuery.disableAnimationsOf(context);
    final paused = session.paused;
    final digits = leadIn ? session.leadLeft : session.holdLeft;
    final caption = paused ? 'Paused' : (leadIn ? 'Get ready' : 'seconds left');
    return PageScaffold(
      title: 'Mobility 10',
      subtitle: 'Stretch ${hold.stretchIndex + 1} of ${session.stretchCount}',
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
          Row(
            children: [
              _TextAction(label: 'Back', onTap: session.canGoBack ? onBack : null),
              const Spacer(),
              _TextAction(label: 'End', onTap: onClose),
              const Spacer(),
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
        if (e.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          HowToPhotos(urls: e.imageUrls, name: e.name),
        ],
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
    required this.minutes,
    required this.logging,
    required this.error,
    required this.onRetry,
    required this.onDone,
  });

  final int minutes;
  final _Logging logging;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final unit = minutes == 1 ? 'minute' : 'minutes';
    final failed = logging == _Logging.failed;
    return PageScaffold(
      title: 'Mobility 10',
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
        Semantics(header: true, child: const Text('Nice work', style: AppText.display)),
        const SizedBox(height: 8),
        Text('$minutes $unit of mobility.', style: AppText.headline),
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
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: context.accentPalette.lip,
        disabledForegroundColor: kInkMuted,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
