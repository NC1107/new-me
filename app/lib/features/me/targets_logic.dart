import '../../api/models.dart';
import '../../util/format.dart';
import '../health/health_metrics.dart';

/// A page section and the targets it lists, in the order the research doc presents them.
class TargetGroup {
  const TargetGroup(this.title, this.keys);

  final String title;
  final List<String> keys;
}

const kTargetGroups = [
  TargetGroup('Energy', ['restingEnergy', 'maintenance', 'calories']),
  TargetGroup('Macros', ['protein', 'fat', 'saturatedFatMax', 'carbs', 'fiber']),
  TargetGroup('Sleep', ['sleep']),
  TargetGroup('Activity', ['activity']),
  TargetGroup('Steps', ['steps']),
  TargetGroup('Push-ups', ['pushups']),
];

/// The estimate from logs is a secondary line under maintenance, not a row of its own.
const kEstimateKey = 'estimatedFromLogs';

const _names = {
  'restingEnergy': 'Resting energy',
  'maintenance': 'Maintenance',
  'estimatedFromLogs': 'Estimated from your logs',
  'calories': 'Calories',
  'protein': 'Protein',
  'fat': 'Fat',
  'saturatedFatMax': 'Saturated fat (max)',
  'carbs': 'Carbohydrate',
  'fiber': 'Fiber',
  'sleep': 'Sleep',
  'activity': 'Activity',
  'steps': 'Steps',
  'pushups': 'Push-ups',
};

String targetName(String key) => _names[key] ?? key;

/// "2,300 kcal", "7 h 30 min" for minutes, "150 min a week".
String formatTargetValue(int value, String unit) {
  if (unit == 'min') return formatDuration(value);
  return unit.isEmpty ? value.formatted : '${value.formatted} $unit';
}

/// Where a missing input is fixed.
enum FixAt { profile, health, pushupMax }

class MissingItem {
  const MissingItem(this.key, this.label, this.hint, this.fix);

  final String key;
  final String label;
  final String hint;
  final FixAt fix;
}

const _missingCopy = {
  'weightKg': MissingItem(
    'weightKg',
    'Weight',
    'Log a weigh-in, or let Apple Health share one',
    FixAt.health,
  ),
  'heightCm': MissingItem(
    'heightCm',
    'Height',
    'Add it in Profile, or let Apple Health share it',
    FixAt.profile,
  ),
  'age': MissingItem('age', 'Birth year', 'Add it in Profile', FixAt.profile),
  'sex': MissingItem('sex', 'Sex', 'Choose it in Profile', FixAt.profile),
  'steps14': MissingItem(
    'steps14',
    'Steps',
    'Needs 5 days of steps from Apple Health in the last 14',
    FixAt.health,
  ),
  'pushupMax': MissingItem(
    'pushupMax',
    'Push-up max test',
    'Record one set to near failure',
    FixAt.pushupMax,
  ),
};

/// The inputs and data that keep a target empty, once each, in the order they are needed.
/// Reasons the server words itself (the log estimate's thresholds) stay on their own row.
List<MissingItem> missingItems(TargetsReport report) {
  final keys = <String>{
    for (final i in report.missingInputs) i.key,
    for (final t in report.targets)
      if (t.key != kEstimateKey) ...t.missing,
  };
  return [
    for (final key in _missingCopy.keys)
      if (keys.contains(key)) _missingCopy[key]!,
  ];
}

/// The targets "Use all" would apply: the ones that have a value that is not already the setting.
List<Target> usable(TargetsReport report) => [
  for (final t in report.targets)
    if (t.canUse) t,
];

/// What the toast says after applying. Open days are scored first, so a change starts tomorrow.
String appliedToast(List<Target> applied) {
  if (applied.isEmpty) return 'Nothing to change';
  final parts = [
    for (final t in applied) '${targetName(t.key)} ${formatTargetValue(t.value!, t.unit)}',
  ];
  return 'Starts tomorrow: ${parts.join(', ')}';
}

/// Short lines under a target from its `details`, which the server fills per target.
List<String> detailLines(Target t) {
  final d = t.details;
  String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
  final out = <String>[];
  void add(String? s) {
    if (s != null) out.add(s);
  }

  switch (t.key) {
    case 'protein':
      add(str(d['perMealTip']));
      add(str(d['capNote']));
    case 'maintenance':
      add(str(d['note']));
    case 'carbs':
      add(str(d['context']));
    case 'activity':
      add(str(d['note']));
    case 'sleep':
      final bed = d['bedtime'];
      if (bed is Map) {
        final work = str(bed['workday']), off = str(bed['dayOff']);
        if (work != null) {
          add('Bedtime $work${off != null && off != work ? ' ($off on days off)' : ''}');
        }
      }
      final short = d['shortfall7'];
      if (short is Map && short['shortfallMin'] is num) {
        final min = (short['shortfallMin'] as num).toInt();
        add(
          min == 0
              ? 'Last 7 nights: no shortfall against your target'
              : 'Last 7 nights: ${formatDuration(min)} short of your target',
        );
        add(str(short['note']));
      }
      final reg = d['regularity'];
      if (reg is Map) {
        final score = reg['score'];
        if (score is num) {
          add('Sleep Regularity Index ${score.round()} of 100');
          add(str(reg['advice']));
        } else {
          add('Sleep Regularity Index needs more nights with sleep');
        }
        add(str(reg['note']));
      }
    case 'pushups':
      final range = d['rangePerSet'];
      final max = d['latestMax'];
      if (max is num) {
        final span = range is List && range.length == 2
            ? ' (70 to 80% is ${range[0]} to ${range[1]})'
            : '';
        add('Latest max test: ${max.round()} reps$span');
      }
      if (d['suggestRetestEveryWeeks'] is String) {
        add('Retest every ${d['suggestRetestEveryWeeks']} weeks');
      }
  }
  return out;
}
