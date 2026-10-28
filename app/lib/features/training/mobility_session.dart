import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

/// Mobility 10, in New Me's own order: floor work first, then lying, then standing. The order is
/// not from a trial, and the page says so. A key the server does not know is skipped.
const kMobilitySequence = [
  'cat_stretch',
  'childs_pose',
  'kneeling_hip_flexor_stretch',
  'seated_hamstring_stretch',
  'figure_four_stretch',
  'knee_across_body_stretch',
  'standing_calf_stretch',
  'standing_trunk_twist',
  'cross_body_shoulder_stretch',
  'triceps_stretch',
];

/// 60 seconds per stretch (Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334),
/// done as two holds. A stretch done on each side takes one hold per side.
const kMobilityHoldSeconds = 30;

/// Under this much time a stopped session is not worth logging.
const kMobilityMinLogSeconds = 30;

const kMobilityCitation =
    'Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334: 60 seconds per '
    'stretch, at least 2 days a week.';

const kMobilityOrderNote =
    'The order is New Me\'s own sequence, not from a trial. Each stretch is 60 seconds as two '
    '30 second holds, one per side where it has sides.';

/// One timed hold: which stretch it belongs to and how to tell it apart from its other hold.
@immutable
class MobilityHold {
  const MobilityHold({
    required this.exercise,
    required this.stretchIndex,
    required this.label,
    required this.firstOfStretch,
  });

  final Exercise exercise;
  final int stretchIndex;

  /// "Left side", "Right side", or "Hold 1 of 2".
  final String label;
  final bool firstOfStretch;
}

/// The holds of Mobility 10 in order, for the stretches the catalog has.
List<MobilityHold> buildMobilityHolds(ExerciseCatalog catalog) {
  final stretches = [
    for (final key in kMobilitySequence)
      if (catalog.byKey(key) case final e? when e.stretch) e,
  ];
  return [
    for (final (i, e) in stretches.indexed) ...[
      MobilityHold(
        exercise: e,
        stretchIndex: i,
        label: e.perSide ? 'Left side' : 'Hold 1 of 2',
        firstOfStretch: true,
      ),
      MobilityHold(
        exercise: e,
        stretchIndex: i,
        label: e.perSide ? 'Right side' : 'Hold 2 of 2',
        firstOfStretch: false,
      ),
    ],
  ];
}

enum MobilityPhase { leadIn, hold, done }

/// What a tick did, so the page can answer with a haptic and an announcement.
enum MobilityEvent { leadInTick, go, nextHold, finished }

/// The session clock as plain state: one [tick] per second of active time, a 3 second lead-in
/// before every hold, auto-advance, pause, skip and back. It never reads the wall clock, so the
/// page can replay seconds spent in the background.
class MobilityController extends ChangeNotifier {
  MobilityController(this.holds) : assert(holds.isNotEmpty);

  final List<MobilityHold> holds;

  int _index = 0;
  MobilityPhase _phase = MobilityPhase.leadIn;
  int _leadLeft = kHoldLeadInSeconds;
  int _holdLeft = kMobilityHoldSeconds;
  int _active = 0;
  bool _paused = false;

  int get index => _index;
  MobilityHold get current => holds[_index];
  MobilityPhase get phase => _phase;
  int get leadLeft => _leadLeft;
  int get holdLeft => _holdLeft;
  bool get paused => _paused;
  bool get finished => _phase == MobilityPhase.done;

  /// Seconds the session has run, lead-ins included and pauses not.
  int get activeSeconds => _active;

  int get stretchCount => holds.last.stretchIndex + 1;

  /// Whole-session progress from 0 to 1, counted in hold time.
  double get progress {
    if (finished) return 1;
    final held = _phase == MobilityPhase.hold ? kMobilityHoldSeconds - _holdLeft : 0;
    return (_index * kMobilityHoldSeconds + held) / (holds.length * kMobilityHoldSeconds);
  }

  /// Minutes to log: the active time rounded to the nearest minute, at least one.
  int get minutes => math.max(1, (_active / 60).round());

  bool get worthLogging => _active >= kMobilityMinLogSeconds;

  /// Advances one second. Returns null while paused or finished.
  MobilityEvent? tick() {
    if (_paused || finished) return null;
    _active += 1;
    if (_phase == MobilityPhase.leadIn) {
      _leadLeft -= 1;
      if (_leadLeft > 0) {
        notifyListeners();
        return MobilityEvent.leadInTick;
      }
      _phase = MobilityPhase.hold;
      _holdLeft = kMobilityHoldSeconds;
      notifyListeners();
      return MobilityEvent.go;
    }
    _holdLeft -= 1;
    if (_holdLeft > 0) {
      notifyListeners();
      return null;
    }
    if (_index == holds.length - 1) {
      _phase = MobilityPhase.done;
      notifyListeners();
      return MobilityEvent.finished;
    }
    _start(_index + 1);
    return MobilityEvent.nextHold;
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

  /// Jumps to the first hold of the next stretch, or finishes after the last one.
  void skipStretch() {
    if (finished) return;
    final next = holds.indexWhere((h) => h.stretchIndex > current.stretchIndex);
    if (next < 0) {
      _phase = MobilityPhase.done;
      notifyListeners();
    } else {
      _start(next);
    }
  }

  /// Restarts the current stretch, or goes to the one before when already at its start.
  void backStretch() {
    if (finished) return;
    final atStart = current.firstOfStretch && _phase == MobilityPhase.leadIn;
    final target = atStart ? current.stretchIndex - 1 : current.stretchIndex;
    if (target < 0) return;
    _start(holds.indexWhere((h) => h.stretchIndex == target));
  }

  bool get canGoBack =>
      !finished && (index > 0 || !(current.firstOfStretch && _phase == MobilityPhase.leadIn));

  void _start(int index) {
    _index = index;
    _phase = MobilityPhase.leadIn;
    _leadLeft = kHoldLeadInSeconds;
    _holdLeft = kMobilityHoldSeconds;
    notifyListeners();
  }
}
