import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

/// Under this much time a stopped session is not worth logging.
const kGuidedMinLogSeconds = 30;

/// One timed hold of a guided routine: which stretch or pose it belongs to, how long it lasts,
/// and how to tell it apart from the other holds of the same step.
@immutable
class GuidedHold {
  const GuidedHold({
    required this.exercise,
    required this.stepIndex,
    required this.label,
    required this.firstOfStep,
    required this.seconds,
  });

  final Exercise exercise;

  /// The stretch or pose this hold belongs to, counted from 0 in the routine.
  final int stepIndex;

  /// "Left side", "Hold 1 of 2", or a short instruction.
  final String label;
  final bool firstOfStep;
  final int seconds;
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

/// Seconds a routine takes with its lead-ins, for the intro's "about N minutes".
int guidedTotalSeconds(List<GuidedHold> holds) =>
    holds.fold(0, (sum, h) => sum + h.seconds + kHoldLeadInSeconds);

/// The session clock as plain state: one [tick] per second of active time, a 3 second lead-in
/// before every hold, auto-advance, pause, skip and back. It never reads the wall clock, so the
/// page can replay seconds spent in the background. Mobility and yoga share it.
class GuidedController extends ChangeNotifier {
  GuidedController(this.holds) : assert(holds.isNotEmpty) {
    _holdLeft = holds.first.seconds;
  }

  final List<GuidedHold> holds;

  int _index = 0;
  GuidedPhase _phase = GuidedPhase.leadIn;
  int _leadLeft = kHoldLeadInSeconds;
  late int _holdLeft;
  int _active = 0;
  bool _paused = false;

  int get index => _index;
  GuidedHold get current => holds[_index];

  /// The hold after this one, or null on the last.
  GuidedHold? get next => _index + 1 < holds.length ? holds[_index + 1] : null;
  GuidedPhase get phase => _phase;
  int get leadLeft => _leadLeft;
  int get holdLeft => _holdLeft;
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
    final held = _phase == GuidedPhase.hold ? current.seconds - _holdLeft : 0;
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
      notifyListeners();
      return GuidedEvent.go;
    }
    _holdLeft -= 1;
    if (_holdLeft > 0) {
      notifyListeners();
      if (_holdLeft <= kGuidedCountdownSeconds) return GuidedEvent.countdown;
      if (current.seconds >= kGuidedHalfwayMinSeconds &&
          current.seconds - _holdLeft == current.seconds ~/ 2) {
        return GuidedEvent.halfway;
      }
      return null;
    }
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
    _phase = GuidedPhase.leadIn;
    _leadLeft = kHoldLeadInSeconds;
    _holdLeft = holds[index].seconds;
    notifyListeners();
  }
}
