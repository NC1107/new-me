import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

/// Under this much time a stopped session is not worth logging.
const kGuidedMinLogSeconds = 30;

/// What a hold asks of the person: a countdown, a number of reps at their own pace, or a rest.
enum GuidedKind { timed, reps, rest }

/// One hold of a guided routine: which stretch, pose or exercise it belongs to, how long it
/// lasts, and how to tell it apart from the other holds of the same step. A [GuidedKind.reps]
/// hold has no countdown: it waits for the person to say they are done.
@immutable
class GuidedHold {
  const GuidedHold({
    required this.exercise,
    required this.stepIndex,
    required this.label,
    required this.firstOfStep,
    required this.seconds,
    this.kind = GuidedKind.timed,
    this.reps = 0,
    this.round = 0,
    this.rounds = 0,
    this.section = '',
  });

  final Exercise exercise;

  /// The stretch or pose this hold belongs to, counted from 0 in the routine.
  final int stepIndex;

  /// "Left side", "Hold 1 of 2", or a short instruction.
  final String label;
  final bool firstOfStep;

  /// The countdown of a timed hold or a rest. For a rep hold it is only the estimate that sizes
  /// the progress bar and the minutes on the intro, since the person sets the pace.
  final int seconds;
  final GuidedKind kind;

  /// The target of a rep hold.
  final int reps;

  /// Which round of a circuit this hold is in, counted from 1, and how many there are; 0 outside one.
  final int round;
  final int rounds;

  /// "Warm-up", "Circuit" or "Cool-down" for a calisthenics hold; empty elsewhere.
  final String section;

  bool get isReps => kind == GuidedKind.reps;
  bool get isRest => kind == GuidedKind.rest;
  bool get lastRound => rounds > 1 && round == rounds;
}

enum GuidedPhase { leadIn, hold, done }

/// What a tick did, so the page can answer with a haptic, a sound and an announcement.
/// [countdown] is 3, 2 and 1 seconds before a hold ends and [halfway] the midpoint of a hold of
/// [kGuidedHalfwayMinSeconds] or more.
enum GuidedEvent { leadInTick, go, countdown, halfway, nextHold, finished }

/// Shorter holds get no halfway tone, so they are not noisy.
const kGuidedHalfwayMinSeconds = 20;

/// The last seconds of a hold that tick.
const kGuidedCountdownSeconds = 3;

/// Seconds a routine takes with its lead-ins, for the intro's "about N minutes". A rest has no
/// lead-in.
int guidedTotalSeconds(List<GuidedHold> holds) =>
    holds.fold(0, (sum, h) => sum + h.seconds + (h.isRest ? 0 : kHoldLeadInSeconds));

/// The session clock as plain state: one [tick] per second of active time, a 3 second lead-in
/// before every hold but a rest, auto-advance, pause, skip and back. A rep hold stops the
/// countdown and waits for [complete]. It never reads the wall clock, so the page can replay
/// seconds spent in the background. Mobility, yoga and calisthenics share it.
class GuidedController extends ChangeNotifier {
  GuidedController(this.holds) : assert(holds.isNotEmpty) {
    _holdLeft = holds.first.seconds;
  }

  static const maxReps = 999;

  final List<GuidedHold> holds;

  int _index = 0;
  GuidedPhase _phase = GuidedPhase.leadIn;
  int _leadLeft = kHoldLeadInSeconds;
  late int _holdLeft;
  int _active = 0;
  int _elapsed = 0;
  bool _paused = false;
  // Reps the person set before tapping Done, and the reps of the holds they finished.
  final Map<int, int> _adjusted = {};
  final Map<int, int> _completed = {};

  int get index => _index;
  GuidedHold get current => holds[_index];

  /// The hold after this one, or null on the last.
  GuidedHold? get next => _index + 1 < holds.length ? holds[_index + 1] : null;
  GuidedPhase get phase => _phase;
  int get leadLeft => _leadLeft;
  int get holdLeft => _holdLeft;

  /// Seconds into the current hold, which a rep hold counts up because it has no countdown.
  int get holdElapsed => current.isReps ? _elapsed : current.seconds - _holdLeft;

  /// A rep hold the person is doing now, which only [complete] ends.
  bool get awaitingDone => _phase == GuidedPhase.hold && current.isReps && !finished;

  /// The reps to do on the current rep hold: the target unless the person changed it.
  int get currentReps => _adjusted[_index] ?? current.reps;

  void adjustReps(int delta) {
    if (!current.isReps || finished) return;
    final next = (currentReps + delta).clamp(1, maxReps);
    if (next == currentReps) return;
    _adjusted[_index] = next;
    notifyListeners();
  }

  /// Reps finished per catalog exercise, as set by the person before Done. Skipped holds add none.
  Map<String, int> get repsDone {
    final out = <String, int>{};
    _completed.forEach((i, reps) {
      final key = holds[i].exercise.key;
      out[key] = (out[key] ?? 0) + reps;
    });
    return out;
  }

  bool get paused => _paused;
  bool get finished => _phase == GuidedPhase.done;

  /// Seconds the session has run, lead-ins included and pauses not.
  int get activeSeconds => _active;

  int get stepCount => holds.last.stepIndex + 1;

  /// Whole-session progress from 0 to 1, counted in hold time.
  double get progress {
    if (finished) return 1;
    final total = holds.fold(0, (sum, h) => sum + h.seconds);
    final before = holds.take(_index).fold(0, (sum, h) => sum + h.seconds);
    final held = _phase == GuidedPhase.hold && !current.isReps ? current.seconds - _holdLeft : 0;
    return (before + held) / total;
  }

  /// Minutes to log: the active time rounded to the nearest minute, at least one.
  int get minutes => math.max(1, (_active / 60).round());

  bool get worthLogging => _active >= kGuidedMinLogSeconds;

  /// Advances one second. Returns null while paused or finished.
  GuidedEvent? tick() {
    if (_paused || finished) return null;
    _active += 1;
    if (_phase == GuidedPhase.leadIn) {
      _leadLeft -= 1;
      if (_leadLeft > 0) {
        notifyListeners();
        return GuidedEvent.leadInTick;
      }
      _phase = GuidedPhase.hold;
      _holdLeft = current.seconds;
      _elapsed = 0;
      notifyListeners();
      return GuidedEvent.go;
    }
    if (current.isReps) {
      _elapsed += 1;
      return null;
    }
    _holdLeft -= 1;
    if (_holdLeft > 0) {
      notifyListeners();
      if (_holdLeft <= kGuidedCountdownSeconds) return GuidedEvent.countdown;
      if (!current.isRest &&
          current.seconds >= kGuidedHalfwayMinSeconds &&
          current.seconds - _holdLeft == current.seconds ~/ 2) {
        return GuidedEvent.halfway;
      }
      return null;
    }
    return _advance();
  }

  /// The person finished the reps of the current rep hold. Returns null when no rep hold is
  /// being done, or while paused.
  GuidedEvent? complete() {
    if (_paused || !awaitingDone) return null;
    _completed[_index] = currentReps;
    return _advance();
  }

  GuidedEvent _advance() {
    if (_index == holds.length - 1) {
      _phase = GuidedPhase.done;
      notifyListeners();
      return GuidedEvent.finished;
    }
    _start(_index + 1);
    return GuidedEvent.nextHold;
  }

  void pause() {
    if (_paused || finished) return;
    _paused = true;
    notifyListeners();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
  }

  /// Jumps to the first hold of the next step, or finishes after the last one.
  void skipStep() {
    if (finished) return;
    final next = holds.indexWhere((h) => h.stepIndex > current.stepIndex);
    if (next < 0) {
      _phase = GuidedPhase.done;
      notifyListeners();
    } else {
      _start(next);
    }
  }

  /// Restarts the current step, or goes to the one before when already at its start.
  void backStep() {
    if (finished) return;
    final atStart = current.firstOfStep && _phase == GuidedPhase.leadIn;
    final target = atStart ? current.stepIndex - 1 : current.stepIndex;
    if (target < 0) return;
    _start(holds.indexWhere((h) => h.stepIndex == target));
  }

  bool get canGoBack =>
      !finished && (index > 0 || !(current.firstOfStep && _phase == GuidedPhase.leadIn));

  void _start(int index) {
    _index = index;
    _elapsed = 0;
    _adjusted.remove(index);
    _completed.remove(index);
    final rest = holds[index].isRest;
    _phase = rest ? GuidedPhase.hold : GuidedPhase.leadIn;
    _leadLeft = rest ? 0 : kHoldLeadInSeconds;
    _holdLeft = holds[index].seconds;
    notifyListeners();
  }
}
