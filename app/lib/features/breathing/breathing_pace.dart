import 'package:flutter/animation.dart';

/// What the person does during one step of a breath.
enum BreathPhase { inhale, topUp, exhale }

/// One step of a breath: how long it lasts and how big the pacer is at its start and end, as a
/// share of its full size.
class BreathStep {
  const BreathStep(this.phase, this.seconds, this.from, this.to);

  final BreathPhase phase;
  final int seconds;
  final double from;
  final double to;
}

/// Where a session stands at one moment.
class BreathCue {
  const BreathCue({
    required this.step,
    required this.stepIndex,
    required this.secondsLeft,
    required this.scale,
    required this.breaths,
  });

  final BreathStep step;
  final int stepIndex;

  /// Whole seconds still to go in this step, counting down to 1.
  final int secondsLeft;

  /// The pacer's size now, from 0 to 1.
  final double scale;

  /// Breaths finished so far.
  final int breaths;
}

/// A way of breathing: a loop of steps.
///
/// The cyclic sighing steps follow Balban et al., Cell Rep Med 2023;4:100895: two inhales through
/// the nose, the second topping up the first, then a long exhale through the mouth. The paper
/// does not time the steps, so the 2, 1 and 5 seconds are a product choice that keeps the
/// exhale longer than both inhales together. Slow breathing is 5 seconds in and 5 out, which is
/// 6 breaths a minute (0.1 Hz), the rate most studies in Zaccaro et al., Front Hum Neurosci
/// 2018;12:353, used.
class BreathingPace {
  const BreathingPace({
    required this.id,
    required this.name,
    required this.blurb,
    required this.steps,
  });

  final String id;
  final String name;

  /// One sentence on how to breathe.
  final String blurb;
  final List<BreathStep> steps;

  int get cycleSeconds => steps.fold(0, (sum, s) => sum + s.seconds);

  double get breathsPerMinute => 60 / cycleSeconds;

  /// The state of the session [elapsed] after it began. Time loops through the steps.
  BreathCue at(Duration elapsed) {
    final cycle = cycleSeconds * 1000;
    final ms = elapsed.inMilliseconds;
    final inCycle = ms % cycle;
    var start = 0;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final end = start + s.seconds * 1000;
      if (inCycle < end) {
        final t = (inCycle - start) / (s.seconds * 1000);
        return BreathCue(
          step: s,
          stepIndex: i,
          secondsLeft: ((end - inCycle) / 1000).ceil(),
          scale: s.from + (s.to - s.from) * Curves.easeInOut.transform(t),
          breaths: ms ~/ cycle,
        );
      }
      start = end;
    }
    throw StateError('unreachable: inCycle is always inside the cycle');
  }
}

const kCyclicSighing = BreathingPace(
  id: 'sighing',
  name: 'Cyclic sighing',
  blurb:
      'Breathe in through your nose, then a second short sip of air on top, '
      'then a long, slow breath out through your mouth.',
  steps: [
    BreathStep(BreathPhase.inhale, 2, 0.5, 0.8),
    BreathStep(BreathPhase.topUp, 1, 0.8, 1),
    BreathStep(BreathPhase.exhale, 5, 1, 0.5),
  ],
);

const kSlowBreathing = BreathingPace(
  id: 'slow',
  name: 'Slow breathing',
  blurb: 'Five seconds in through your nose and five seconds out, about 6 breaths a minute.',
  steps: [BreathStep(BreathPhase.inhale, 5, 0.5, 1), BreathStep(BreathPhase.exhale, 5, 1, 0.5)],
);

const kBreathingPaces = [kCyclicSighing, kSlowBreathing];

/// The session length that earns the daily quest, from Balban et al. 2023.
const kBreathingSession = Duration(minutes: 5);

/// The most minutes one entry may hold, matching the server.
const kMaxBreathingMinutes = 120;

String phaseCue(BreathPhase p) => switch (p) {
  BreathPhase.inhale => 'Breathe in through your nose',
  BreathPhase.topUp => 'A second sip of air on top',
  BreathPhase.exhale => 'Long breath out through your mouth',
};

/// The short word on the pacer.
String phaseWord(BreathPhase p) => switch (p) {
  BreathPhase.inhale => 'In',
  BreathPhase.topUp => 'Top up',
  BreathPhase.exhale => 'Out',
};

/// "4:32".
String clockText(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
