import '../../api/models.dart';
import '../../util/format.dart';
import '../health/health_metrics.dart';
import '../onboarding/goal_catalog.dart';
import '../setup/about_you.dart';

/// A page section and the targets it lists. [hasYours] is false for sections of facts about the
/// body, which have no setting of the person's own to set beside the figure.
class TargetGroup {
  const TargetGroup(this.title, this.keys, {this.hasYours = true});

  final String title;
  final List<String> keys;
  final bool hasYours;
}

const kTargetGroups = [
  TargetGroup('Your body', ['restingEnergy', 'maintenance'], hasYours: false),
  TargetGroup('Food', ['calories', 'protein', 'fat', 'saturatedFatMax', 'carbs', 'fiber']),
  TargetGroup('Move and rest', ['steps', 'exercise', 'activity', 'sleep', 'pushups']),
  TargetGroup('Habits', ['water', 'produce', 'breathing']),
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
  'saturatedFatMax': 'Saturated fat, at most',
  'carbs': 'Carbohydrate',
  'fiber': 'Fiber',
  'sleep': 'Sleep',
  'activity': 'Activity a week',
  'exercise': 'Exercise',
  'steps': 'Steps',
  'pushups': 'Push-ups',
  'water': 'Water',
  'produce': 'Fruit and vegetables',
  'breathing': 'Breathing',
};

String targetName(String key) => _names[key] ?? key;

/// "2,300 kcal", "7 h 30 min" for minutes, "150 min a week", "2.2 L" or "74 fl oz" for water.
String formatTargetValue(int value, String unit, {Units units = Units.metric}) {
  if (unit == 'min') return formatDuration(value);
  if (unit == 'ml') return units.volume(value);
  if (unit == 'servings') return '${value.formatted} servings (${value * kProduceServingGrams} g)';
  return unit.isEmpty ? value.formatted : '${value.formatted} $unit';
}

/// Where a missing input is fixed.
enum FixAt { aboutYou, health, pushupMax }

class MissingItem {
  const MissingItem(this.key, this.label, this.hint, this.fix, {this.question});

  final String key;
  final String label;
  final String hint;
  final FixAt fix;

  /// The About you question that supplies this input, for [FixAt.aboutYou].
  final AboutQuestion? question;
}

const _missingCopy = {
  'weightKg': MissingItem(
    'weightKg',
    'Weight',
    'Enter it, or let Apple Health share one',
    FixAt.aboutYou,
    question: AboutQuestion.weight,
  ),
  'heightCm': MissingItem(
    'heightCm',
    'Height',
    'Enter it, or let Apple Health share it',
    FixAt.aboutYou,
    question: AboutQuestion.height,
  ),
  'age': MissingItem(
    'age',
    'Birth year',
    'Add it in About you',
    FixAt.aboutYou,
    question: AboutQuestion.birthYear,
  ),
  'sex': MissingItem(
    'sex',
    'Sex',
    'Choose it in About you',
    FixAt.aboutYou,
    question: AboutQuestion.sex,
  ),
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

/// The push-up card's own way to the max test.
final kPushupMaxItem = _missingCopy['pushupMax']!;

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

/// What the toast says after applying.
String appliedToast(List<Target> applied, {Units units = Units.metric}) {
  if (applied.isEmpty) return 'Nothing to change';
  final parts = [
    for (final t in applied)
      '${targetName(t.key)} ${formatTargetValue(t.value!, t.unit, units: units)}',
  ];
  return 'Applied today: ${parts.join(', ')}';
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
    case 'produce':
      final examples = d['servingExamples'];
      if (examples is List && examples.isNotEmpty) {
        add('One serving is $kProduceServingGrams g: ${examples.whereType<String>().join(', ')}.');
      }
      add(str(d['note']));
    case 'water' || 'breathing':
      add(str(d['note']));
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
