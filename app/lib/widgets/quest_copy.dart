import '../api/models.dart';
import '../util/format.dart';
import '../util/reps_exercises.dart';
import '../util/time_format.dart';

/// Quests Apple Health fills in; everything else is logged by hand.
const kAutomaticQuests = {'steps', 'exercise', 'sleep', 'sleep_regularity'};

/// The earlier nights the steady bedtime needs before it can judge one, matching the server.
const kRegularityBaselineNights = 3;

bool isAutomaticQuest(String key) => kAutomaticQuests.contains(key);

/// 450 as "7 h 30 min", 420 as "7 h", 45 as "45 min".
String durationLabel(num minutes) {
  final total = minutes.round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String _unitWord(Quest q, num n) => switch (q.unit) {
  'reps' => repsNoun(q.exercise, n),
  'g' => 'g',
  'meals' => n == 1 ? 'meal' : 'meals',
  _ => shortUnit(q.unit),
};

/// The plain-words title: "Walk 8,000 steps", never "steps quest target".
String questTitle(Quest q, {Units units = Units.metric}) {
  final t = q.target;
  return switch (q.key) {
    'steps' => 'Walk ${t.formatted} steps',
    // A planned session or a Health strength workout completes it too, so push-ups are only the
    // fallback and never the headline.
    'pushups' => 'Get stronger',
    'reading' =>
      q.targetAlt == null
          ? 'Read ${t.formatted} ${shortUnit(q.unit)}'
          : 'Read ${t.formatted} ${shortUnit(q.unit)} or ${q.targetAlt!.formatted} '
                '${shortUnit(q.unitAlt ?? 'pages')}',
    'sleep' => 'Sleep ${durationLabel(t)}',
    'exercise' => 'Exercise ${t.formatted} min',
    'meals_logged' => 'Log ${t.formatted} ${t == 1 ? 'meal' : 'meals'}',
    'protein' => 'Eat ${t.formatted} g protein',
    'yoga' => 'Yoga or stretch ${t.formatted} ${shortUnit(q.unit)}',
    'water' => 'Drink ${units.volume(t)}',
    'sleep_regularity' => 'Keep a steady bedtime',
    'produce' => 'Eat ${t.formatted} a day',
    'breathing' => 'Breathe ${t.formatted} min',
    _ => q.title,
  };
}

/// Whether [questTitle] already names the target, so a progress caption would only repeat it.
bool titleStatesTarget(Quest q) => switch (q.key) {
  'pushups' => false,
  'reading' => q.unitAlt == null,
  'sleep_regularity' || 'produce' => false,
  _ => true,
};

/// "2,000 of 8,000 steps", or "12 min + 5 pages" for the two-part reading quest.
String questProgress(Quest q, {Units units = Units.metric}) {
  final alt = q.unitAlt;
  if (alt != null) {
    final actualAlt = q.actualAlt ?? 0;
    if (q.actual == 0 && actualAlt == 0) return 'Not started';
    return '${q.actual.formatted} ${shortUnit(q.unit)} + ${actualAlt.formatted} ${shortUnit(alt)}';
  }
  if (q.key == 'pushups' && !q.done) {
    return q.actual == 0
        ? 'A strength session or ${q.target.formatted} ${repsNoun(q.exercise, q.target)}'
        : '${q.actual.formatted} of ${q.target.formatted} ${repsNoun(q.exercise, q.target)}, '
              'or a strength workout';
  }
  if (q.key == 'water') {
    return '${units.volumeNumber(q.actual)} of ${units.volume(q.target)}';
  }
  if (q.key == 'produce') {
    return '${q.actual.formatted} of ${q.target.formatted} '
        '${q.target == 1 ? 'serving' : 'servings'} of fruit and veg';
  }
  if (q.key == 'sleep_regularity') return steadyBedtimeProgress(q);
  if (q.key == 'sleep') {
    return q.actual == 0
        ? 'No sleep recorded'
        : '${durationLabel(q.actual)} of ${durationLabel(q.target)}';
  }
  return '${q.actual.formatted} of ${q.target.formatted} ${_unitWord(q, q.target)}';
}

/// The amount so far, beside the bar, for a card whose title already states the target:
/// "4,321", "7 h 12 min", "25 min". Null when there is nothing yet.
String? questActualLabel(Quest q, {Units units = Units.metric}) {
  if (q.actual <= 0 || q.unitAlt != null) return null;
  if (q.key == 'water') return units.volume(q.actual);
  return switch (q.unit) {
    'min' || 'minutes' => durationLabel(q.actual),
    'steps' => q.actual.formatted,
    _ => '${q.actual.formatted} ${_unitWord(q, q.actual)}',
  };
}

String _workoutName(String type) => switch (type) {
  'strength' => 'Strength',
  'hiit' => 'HIIT',
  'yoga' => 'Yoga',
  '' => 'Health',
  _ => '${type[0].toUpperCase()}${type.substring(1)}',
};

/// "Done by your Strength workout, 42 min", or "Done by your Full body A session": what finished
/// the quest for the person.
String doneByLabel(DoneBy by) => by.kind == 'session'
    ? 'Done by your ${by.type.isEmpty ? 'training' : by.type} session'
    : 'Done by your ${_workoutName(by.type)} workout, ${by.minutes} min';

/// "Listening synced 3 min ago".
String listeningSyncedLabel(DateTime syncedAt, DateTime now) =>
    'Listening synced ${agoLabel(syncedAt, now)}';

/// One of the two times the steady bedtime checks, for the card: the night's time against the
/// person's usual one, and whether it fell inside the window.
class SteadyLine {
  const SteadyLine({required this.text, required this.ok});

  final String text;
  final bool ok;
}

String _steadyTime(int median, int offset) => formatMinutesOfDay((median + offset) % 1440);

SteadyLine _steadyLine(String label, int median, int offset, bool ok) {
  final gap = offset == 0
      ? 'right on your usual'
      : '${offset.abs()} min ${offset > 0 ? 'later' : 'earlier'} than usual';
  return SteadyLine(
    text: '$label ${_steadyTime(median, offset)}, $gap (${formatMinutesOfDay(median)})',
    ok: ok,
  );
}

/// The night's bed and wake time against the usual ones; empty until the night can be judged.
List<SteadyLine> steadyBedtimeLines(Quest q) {
  final d = q.detail;
  if (d == null || d['measurable'] != true) return const [];
  int n(String key) => (d[key] as num? ?? 0).round();
  return [
    _steadyLine('Bed', n('bedMedian'), n('bedOffset'), d['bedOk'] == true),
    _steadyLine('Up', n('wakeMedian'), n('wakeOffset'), d['wakeOk'] == true),
  ];
}

/// "Both inside 45 min", or what the quest is waiting for.
String steadyBedtimeProgress(Quest q) {
  final d = q.detail;
  final window = (d?['windowMin'] as num? ?? q.target).round();
  if (d == null || d['measurable'] != true) {
    final learned = (d?['baselineNights'] as num? ?? 0).round();
    return learned < kRegularityBaselineNights
        ? 'Learning your usual times: $learned of $kRegularityBaselineNights nights'
        : 'No sleep recorded';
  }
  return switch (q.actual.round()) {
    2 => 'Bed and wake time both within $window min of usual',
    1 => 'One of bed and wake time within $window min of usual',
    _ => 'Neither within $window min of usual',
  };
}

/// How much of the quest's bar is filled.
double questFraction(Quest q) {
  if (q.done) return 1;
  return q.points == 0 ? 0 : q.basePoints / q.points;
}
