import '../../api/models.dart';

/// Server metrics measured in kilograms; an imperial person reads them in pounds.
bool _isKg(String unit) => unit == 'kg';

double? _lb(double? kg, Units u) => kg == null ? null : u.weightIn(kg);

MetricChange? _change(MetricChange? c, Units u) =>
    c == null ? null : MetricChange(abs: u.weightIn(c.abs), pct: c.pct, better: c.better);

/// A progress metric in the person's units: weight and lean mass become pounds.
ProgressMetric metricInUnits(ProgressMetric m, Units u) {
  if (!u.isImperial || !_isKg(m.unit)) return m;
  return ProgressMetric(
    key: m.key,
    title: m.title,
    unit: u.weightUnit,
    goodDirection: m.goodDirection,
    current: _lb(m.current, u),
    previous: _lb(m.previous, u),
    first: _lb(m.first, u),
    changeFromPrevious: _change(m.changeFromPrevious, u),
    changeFromFirst: _change(m.changeFromFirst, u),
    series: [for (final p in m.series) SeriesPoint(weekStart: p.weekStart, value: _lb(p.value, u))],
    summary: m.summary,
  );
}

/// An improvement in the person's units.
Improvement improvementInUnits(Improvement i, Units u) {
  if (!u.isImperial || !_isKg(i.unit)) return i;
  return Improvement(
    key: i.key,
    title: i.title,
    unit: u.weightUnit,
    value: u.weightIn(i.value),
    previous: u.weightIn(i.previous),
    pct: i.pct,
    summary: i.summary,
  );
}

/// A look-back month metric in the person's units.
MonthMetric monthMetricInUnits(MonthMetric m, Units u) {
  if (!u.isImperial || !_isKg(m.unit)) return m;
  return MonthMetric(
    key: m.key,
    title: m.title,
    unit: u.weightUnit,
    goodDirection: m.goodDirection,
    value: _lb(m.value, u),
    previous: _lb(m.previous, u),
    first: _lb(m.first, u),
    changeFromPrevious: _change(m.changeFromPrevious, u),
    changeFromFirst: _change(m.changeFromFirst, u),
  );
}
