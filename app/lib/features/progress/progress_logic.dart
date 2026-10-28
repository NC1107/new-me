import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../util/format.dart';
import '../../widgets/quest_copy.dart';

/// Which way a number moved, ignoring whether that is good.
enum Movement { up, down, flat }

/// Whether a change is the good kind, the bad kind, or has no good direction (weight, or under
/// 1%).
enum Tone { good, bad, neutral }

@immutable
class Trend {
  const Trend(this.movement, this.tone);

  final Movement movement;
  final Tone tone;
}

/// The arrow of a change: it points where the number went, and its tone says whether that is the
/// good direction. A missing change reads as flat and neutral.
Trend trendOf(MetricChange? change) {
  if (change == null) return const Trend(Movement.flat, Tone.neutral);
  final flat = change.abs == 0 || (change.pct != null && change.pct!.abs() < 1);
  final movement = flat ? Movement.flat : (change.abs > 0 ? Movement.up : Movement.down);
  final tone = switch (change.better) {
    true => Tone.good,
    false => Tone.bad,
    null => Tone.neutral,
  };
  return Trend(movement, flat ? Tone.neutral : tone);
}

/// The change the card's arrow follows: against the previous window, else the first one.
MetricChange? headlineChange(ProgressMetric m) => m.changeFromPrevious ?? m.changeFromFirst;

bool _isMinutes(String key) => key == 'sleep_minutes';

/// A metric value the way people read it: sleep as hours and minutes, whole numbers with
/// thousands separators, everything else to one decimal.
String formatMetricValue(String key, double value) {
  // Non-breaking, so "7 h 8 min" never splits across lines inside a sentence.
  if (_isMinutes(key)) return durationLabel(value).replaceAll(' ', '\u00A0');
  final rounded = (value * 10).round() / 10;
  return rounded.formatted;
}

/// The unit after a value: "min a day", with sleep's minutes already folded into the value.
String metricUnit(String key, String unit) => _isMinutes(key) ? 'a night' : unit;

String _withUnit(String key, String unit, double value) {
  final u = metricUnit(key, unit);
  return u.isEmpty ? formatMetricValue(key, value) : '${formatMetricValue(key, value)} $u';
}

String firstWindowLabel(int window) =>
    window == 30 ? 'your first month' : 'your first $window days';

String previousWindowLabel(int window) =>
    window == 30 ? 'the previous month' : 'the previous $window days';

/// Whether a card has something to show: a reading, and for habits at least one kept.
bool metricHasData(ProgressMetric m) {
  final current = m.current;
  if (current == null) return false;
  return !(m.key == 'habits_kept' && current == 0);
}

/// Whether a card lacks a trend line or a comparison, so the page explains it once.
bool metricIsSparse(ProgressMetric m) =>
    m.series.where((p) => p.value != null).length < 2 ||
    (m.changeFromPrevious == null && m.changeFromFirst == null);

/// "Reading: 24 min a day, up from 11 in your first month". It compares with the first window
/// when there is one, else with the previous.
String metricSentence(ProgressMetric m, {int window = 30}) {
  final current = m.current;
  if (current == null) return '${m.title}: no data yet';
  final now = '${m.title}: ${_withUnit(m.key, m.unit, current)}';
  final isFirst = m.first != null;
  final ref = m.first ?? m.previous;
  if (ref == null) return now;
  final label = isFirst ? firstWindowLabel(window) : previousWindowLabel(window);
  final a = formatMetricValue(m.key, current), b = formatMetricValue(m.key, ref);
  if (a == b) return '$now, about the same as in $label';
  return '$now, ${current > ref ? 'up' : 'down'} from $b in $label';
}

/// "+13 (+118%)" or "-2 min (-8%)": the size of a change. Sleep's minutes read as a duration.
String changeLabel(String key, MetricChange change) {
  final sign = change.abs > 0 ? '+' : (change.abs < 0 ? '-' : '');
  final size = formatMetricValue(key, change.abs.abs());
  final pct = change.pct;
  if (pct == null) return '$sign$size';
  final pctSign = pct > 0 ? '+' : (pct < 0 ? '-' : '');
  return '$sign$size ($pctSign${pct.abs().round()}%)';
}

/// "No change", "Better" or "Worse" for screen readers, so the arrow is never colour alone.
String toneWord(Trend t) => switch (t.movement) {
  Movement.flat => 'no change',
  _ => switch (t.tone) {
    Tone.good => 'better',
    Tone.bad => 'worse',
    Tone.neutral => t.movement == Movement.up ? 'up' : 'down',
  },
};

/// "vs the previous month: +13 (+118%), better".
String comparisonLabel(String key, String against, MetricChange? change) {
  if (change == null) return 'Not enough days yet vs $against';
  final t = trendOf(change);
  if (t.movement == Movement.flat) return 'About the same as $against';
  return '${changeLabel(key, change)} vs $against, ${toneWord(t)}';
}

/// The smoothed weight's weekly rate: "down 0.3 kg a week" (or pounds), "steady" or null with
/// too little history.
String? weeklyRateLabel(double? kgPerWeek, Units units) {
  if (kgPerWeek == null) return null;
  final rounded = (units.weightIn(kgPerWeek).abs() * 10).round() / 10;
  if (rounded == 0) return 'steady';
  return '${kgPerWeek > 0 ? 'up' : 'down'} ${rounded.formatted} ${units.weightUnit} a week';
}

/// What a sparkline says to a screen reader.
String seriesSummary(ProgressMetric m) {
  final values = [
    for (final p in m.series)
      if (p.value != null) p.value!,
  ];
  if (values.length < 2) return '${m.title} trend, not enough weeks yet';
  return '${m.title} trend over ${values.length} weeks, from '
      '${formatMetricValue(m.key, values.first)} to ${formatMetricValue(m.key, values.last)}';
}

/// The order cards appear in, by key; unknown keys go last in the server's order.
const _kOrder = [
  'reading_minutes',
  'steps',
  'sleep_minutes',
  'workouts',
  'pushups',
  'protein_g',
  'habits_kept',
  'weight_kg',
  'body_fat_pct',
  'lean_mass_kg',
  'vo2max',
  'resting_hr',
];

List<ProgressMetric> orderedMetrics(List<ProgressMetric> metrics) {
  int rank(String k) {
    final i = _kOrder.indexOf(k);
    return i < 0 ? _kOrder.length : i;
  }

  final indexed = metrics.indexed.toList()
    ..sort((a, b) {
      final r = rank(a.$2.key).compareTo(rank(b.$2.key));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// "Reading: 24 min a day, up from 11", the sentence of one improvement. The direction is
/// whichever way the number moved, since "better" can be down (resting heart rate).
String improvementSentence(Improvement i) {
  final value = formatMetricValue(i.key, i.value);
  final unit = metricUnit(i.key, i.unit);
  final word = i.value >= i.previous ? 'up' : 'down';
  return '${i.title}: $value${unit.isEmpty ? '' : ' $unit'}, $word from '
      '${formatMetricValue(i.key, i.previous)}';
}

/// "+118%" for an improvement's relative size.
String improvementPct(Improvement i) => '+${i.pct.round()}%';

/// The month [delta] months from [month] (YYYY-MM), for the look-back's arrows.
String shiftMonth(String month, int delta) {
  final parts = month.split('-');
  final index = int.parse(parts[0]) * 12 + (int.parse(parts[1]) - 1) + delta;
  return '${(index ~/ 12).toString().padLeft(4, '0')}-${(index % 12 + 1).toString().padLeft(2, '0')}';
}

/// The month a look-back card for [today] (yyyy-MM-dd) is about: the one that just ended.
String lookbackMonthFor(String today) => shiftMonth(today.substring(0, 7), -1);
