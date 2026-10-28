import '../../api/models.dart';

/// "22 kg" or "50 lb": a training load in the person's units.
String kgLabel(double kg, Units units) => units.load(kg);

/// "8 reps", "1 rep", "45 s".
String amountLabel(int amount, {required bool timed}) =>
    timed ? '$amount s' : (amount == 1 ? '1 rep' : '$amount reps');

/// "6 to 12 reps", "30 to 60 s": a prescription's range.
String rangeLabel(Prescription p, {required bool timed}) =>
    timed ? '${p.min} to ${p.max} s' : '${p.min} to ${p.max} reps';

/// "2 × 8 reps at 22 kg": what today asks for on one exercise.
String targetLabel(SessionExercise e, Units units) {
  final t = e.target;
  final base = '${t.sets} × ${amountLabel(t.amount, timed: e.timed)}';
  final load = t.loadKg;
  return load == null ? base : '$base at ${kgLabel(load, units)}';
}

/// "8 reps at 22 kg": what one set of today's target asks for.
String perSetLabel(SessionExercise e, Units units) {
  final base = amountLabel(e.target.amount, timed: e.timed);
  final load = e.target.loadKg;
  return load == null ? base : '$base at ${kgLabel(load, units)}';
}

/// "10 reps at 20 kg", "45 s": one logged set.
String setLabel(ExerciseSet s, Units units) {
  final timed = s.seconds != null;
  final base = amountLabel(timed ? s.seconds! : s.reps ?? 0, timed: timed);
  final load = s.loadKg;
  return load == null ? base : '$base at ${kgLabel(load, units)}';
}

/// "2 in reserve" for a logged set, empty when none was logged.
String rirLabel(int? rir) => rir == null ? '' : '$rir in reserve';

/// "1:30": a rest countdown.
String clockLabel(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "3 of 10 sets".
String sessionProgressLabel(TrainingSession s) => '${s.setsLogged} of ${s.setsPlanned} sets';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon" for ISO weekday 1.
String weekdayLabel(int isoWeekday) =>
    isoWeekday >= 1 && isoWeekday <= 7 ? _weekdays[isoWeekday - 1] : '';

/// "Mon, Thu": the training days of a plan in week order.
String planDaysLabel(TrainingPlan plan) {
  final days = [for (final d in plan.days) d.weekday]..sort();
  return days.map(weekdayLabel).join(', ');
}

/// "Best 10 reps at 20 kg, about 26.7 kg one-rep max": an exercise's best set, with the Epley
/// estimate labelled as one.
String bestLabel(SetAmount best, Units units) {
  final timed = best.seconds != null;
  final amount = amountLabel(timed ? best.seconds! : best.reps ?? 0, timed: timed);
  final load = best.loadKg;
  final e1rm = best.e1rmKg;
  final base = load == null ? 'Best $amount' : 'Best $amount at ${kgLabel(load, units)}';
  return e1rm == null ? base : '$base, estimated one-rep max ${kgLabel(e1rm, units)}';
}

/// "Max test 6 reps".
String maxTestLabel(SetAmount max) =>
    'Max test ${amountLabel(max.seconds ?? max.reps ?? 0, timed: max.seconds != null)}';

String _liftValue(Lift l, double v, Units units) => switch (l.measure) {
  'e1rm' => kgLabel(v, units),
  'seconds' => '${v.round()} s',
  _ => '${v.round()}',
};

/// "Pull-up: best set 8, up from 3 in your first month" (docs/design-v9.md, Progress).
String liftLine(Lift l, Units units) {
  final what = l.measure == 'e1rm' ? 'estimated one-rep max' : 'best set';
  final now = '${l.name}: $what ${_liftValue(l, l.value, units)}';
  final first = l.first;
  if (first == null) return '$now, first month logged';
  if (l.value > first) return '$now, up from ${_liftValue(l, first, units)} in your first month';
  if (l.value < first) return '$now, ${_liftValue(l, first, units)} in your first month';
  return '$now, same as your first month';
}
