import '../api/models.dart';
import '../util/format.dart';

/// Quests Apple Health fills in; everything else is logged by hand.
const kAutomaticQuests = {'steps', 'exercise', 'sleep'};

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
  'reps' => 'push-ups',
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
    'yoga' => 'Yoga or stretching for ${t.formatted} ${shortUnit(q.unit)}',
    'water' => 'Drink ${units.volume(t)}',
    _ => q.title,
  };
}

/// Whether [questTitle] already names the target, so a progress caption would only repeat it.
bool titleStatesTarget(Quest q) => switch (q.key) {
  'pushups' => false,
  'reading' => q.unitAlt == null,
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
        ? 'A strength session or ${q.target.formatted} push-ups'
        : '${q.actual.formatted} of ${q.target.formatted} push-ups, or a strength workout';
  }
  if (q.key == 'water') {
    return '${units.volumeNumber(q.actual)} of ${units.volume(q.target)}';
  }
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

/// How much of the quest's bar is filled.
double questFraction(Quest q) {
  if (q.done) return 1;
  return q.points == 0 ? 0 : q.basePoints / q.points;
}
