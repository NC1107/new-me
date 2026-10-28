import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import 'breathing_pace.dart';

enum _Stage { ready, running, paused, done }

/// A guided breathing session. It pops with the whole minutes breathed, which is the full length
/// once the session finishes and zero when it was ended inside the first minute.
class BreathingSessionPage extends StatefulWidget {
  const BreathingSessionPage({super.key, required this.pace, this.length = kBreathingSession});

  final BreathingPace pace;
  final Duration length;

  @override
  State<BreathingSessionPage> createState() => _BreathingSessionPageState();
}

class _BreathingSessionPageState extends State<BreathingSessionPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  _Stage _stage = _Stage.ready;
  Duration _carried = Duration.zero;
  // Moves every frame; only the pacer listens, so the page rebuilds on whole seconds and stages.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  int _lastStep = -1;

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  int get _minutes => _elapsed.value.inMinutes;

  String _leftText(Duration elapsed) => '${clockText(widget.length - elapsed)} left';

  void _tick(Duration sinceStart) {
    final elapsed = _carried + sinceStart;
    if (elapsed >= widget.length) {
      _ticker.stop();
      HapticFeedback.heavyImpact();
      _elapsed.value = widget.length;
      setState(() => _stage = _Stage.done);
      return;
    }
    final cue = widget.pace.at(elapsed);
    final key = cue.breaths * widget.pace.steps.length + cue.stepIndex;
    final stepChanged = key != _lastStep;
    if (stepChanged) {
      _lastStep = key;
      _pulse(cue.step.phase);
    }
    final shownBefore = _leftText(_elapsed.value);
    _elapsed.value = elapsed;
    if (stepChanged || _leftText(elapsed) != shownBefore) setState(() {});
  }

  /// Each phase has its own feel, so the breath can be followed with eyes closed.
  void _pulse(BreathPhase phase) => switch (phase) {
    BreathPhase.inhale => HapticFeedback.lightImpact(),
    BreathPhase.topUp => HapticFeedback.selectionClick(),
    BreathPhase.exhale => HapticFeedback.mediumImpact(),
  };

  void _begin() {
    HapticFeedback.selectionClick();
    setState(() => _stage = _Stage.running);
    _ticker.start();
  }

  void _pause() {
    _ticker.stop();
    HapticFeedback.selectionClick();
    setState(() {
      _carried = _elapsed.value;
      _stage = _Stage.paused;
    });
  }

  void _resume() {
    HapticFeedback.selectionClick();
    setState(() => _stage = _Stage.running);
    _ticker.start();
  }

  void _leave() =>
      Navigator.of(context).pop(_stage == _Stage.done ? widget.length.inMinutes : _minutes);

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('breathing');
    final cue = widget.pace.at(_elapsed.value);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final started = _stage != _Stage.ready;
    final done = _stage == _Stage.done;
    final cueText = switch (_stage) {
      _Stage.ready => 'Get comfortable and begin when you are ready',
      _Stage.paused => 'Paused',
      _Stage.done => 'Well done',
      _Stage.running => phaseCue(cue.step.phase),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    // The close button's own 48pt box already insets its glyph from the edge.
                    padding: const EdgeInsets.fromLTRB(8, 4, kGutter, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _leave,
                          tooltip: done ? 'Close' : 'End session',
                          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                          icon: const Icon(Icons.close_rounded, size: 28, color: kInk),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(widget.pace.name, style: AppText.title),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: kGutter),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: ValueListenableBuilder<Duration>(
                                  valueListenable: _elapsed,
                                  builder: (context, elapsed, _) {
                                    final live = widget.pace.at(elapsed);
                                    return _Pacer(
                                      scale: !started || done || reduce ? 0.75 : live.scale,
                                      word: started && !done ? phaseWord(live.step.phase) : null,
                                      count: _stage == _Stage.running ? live.secondsLeft : null,
                                      fill: palette.tint,
                                      edge: palette.fill,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  cueText,
                                  textAlign: TextAlign.center,
                                  style: AppText.headline,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _stage == _Stage.ready
                                    ? '${widget.pace.blurb} ${durationWords(widget.length)}.'
                                    : done
                                    ? '${widget.length.inMinutes} minutes of breathing.'
                                    : _leftText(_elapsed.value),
                                textAlign: TextAlign.center,
                                style: AppText.body.copyWith(color: kInkSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, kGutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buttons(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buttons() => switch (_stage) {
    _Stage.ready => [
      ChunkyButton(label: 'Begin', icon: Icons.play_arrow_rounded, onPressed: _begin),
    ],
    _Stage.running => [
      ChunkyButton.secondary(label: 'Pause', icon: Icons.pause_rounded, onPressed: _pause),
    ],
    _Stage.paused => [
      ChunkyButton(label: 'Resume', icon: Icons.play_arrow_rounded, onPressed: _resume),
      if (_minutes >= 1) ...[
        const SizedBox(height: 12),
        ChunkyButton.secondary(label: 'End and log $_minutes min', onPressed: _leave),
      ],
    ],
    _Stage.done => [ChunkyButton(label: 'Log ${widget.length.inMinutes} min', onPressed: _leave)],
  };
}

/// "5 minutes", "1 minute".
String durationWords(Duration d) {
  final m = d.inMinutes;
  return m >= 1 ? '$m ${m == 1 ? 'minute' : 'minutes'}' : '${d.inSeconds} seconds';
}

/// The breathing circle. Its size shows the breath; the word and count are spoken by the cue
/// text above them, so this is hidden from screen readers.
class _Pacer extends StatelessWidget {
  const _Pacer({
    required this.scale,
    required this.word,
    required this.count,
    required this.fill,
    required this.edge,
  });

  final double scale;
  final String? word;
  final int? count;
  final Color fill;
  final Color edge;

  static const _full = 240.0;

  @override
  Widget build(BuildContext context) {
    final side = _full * math.min(1, math.max(0, scale));
    return ExcludeSemantics(
      child: SizedBox(
        width: _full,
        height: _full,
        child: Center(
          child: SizedBox(
            width: side,
            height: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: edge, width: kBorderWidth),
              ),
              child: Center(
                child: word == null
                    ? null
                    : MediaQuery.withNoTextScaling(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(word!, style: AppText.headline),
                            if (count != null)
                              Text('$count', style: AppText.tabular(AppText.display)),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
