import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';

/// What the chart plots, in words.
String metricTitle(ChartMetric m) => switch (m) {
  ChartMetric.e1rm => 'Estimated one-rep max',
  ChartMetric.volume => 'Volume load',
  ChartMetric.reps => 'Best reps in a set',
  ChartMetric.seconds => 'Longest hold',
};

/// The note under the chart: where the number comes from and how far to trust it.
String metricNote(ChartMetric m) => switch (m) {
  ChartMetric.e1rm =>
    'Estimated with the Epley formula, load x (1 + reps / 30), from your best set of 1 to 10 '
        'reps each day. How close it is varies from person to person (Nuzzo et al., Sports Med '
        '2024).',
  ChartMetric.volume =>
    'Load x reps of your biggest set each day, for sets above 10 reps, where a one-rep max '
        'estimate is less reliable.',
  ChartMetric.reps => 'Your most reps in one set each day.',
  ChartMetric.seconds => 'Your longest hold each day.',
};

String chartValueLabel(ChartMetric m, double v, Units units) => switch (m) {
  ChartMetric.e1rm || ChartMetric.volume => units.load(v),
  ChartMetric.reps => v.round() == 1 ? '1 rep' : '${v.round()} reps',
  ChartMetric.seconds => '${v.round()} s',
};

String _axisValue(ChartMetric m, double v, Units units) => switch (m) {
  ChartMetric.e1rm || ChartMetric.volume => units.weightIn(v).round().toString(),
  _ => v.round().toString(),
};

String _axisUnit(ChartMetric m, Units units) => switch (m) {
  ChartMetric.e1rm || ChartMetric.volume => units.weightUnit,
  ChartMetric.reps => 'reps',
  ChartMetric.seconds => 's',
};

String _shortDay(String date) => DateFormat('d MMM').format(parseLocalDate(date));

/// The text a screen reader gets in place of the picture.
String chartSummary(ExerciseHistory h, Units units) {
  final points = h.points;
  final metric = h.metric;
  final b = StringBuffer(metricTitle(metric));
  if (h.estimated) b.write(' (estimated)');
  if (points.length < 2) {
    b.write('. Not enough sets yet for a chart.');
    return b.toString();
  }
  final values = points.map((p) => p.value);
  final best = values.reduce(math.max);
  b.write(
    ', ${points.length} days from ${_shortDay(points.first.date)} to ${_shortDay(points.last.date)}. '
    'First ${chartValueLabel(metric, points.first.value, units)}, '
    'latest ${chartValueLabel(metric, points.last.value, units)}, '
    'best ${chartValueLabel(metric, best, units)}.',
  );
  if (h.maxTests.isNotEmpty) {
    final tests = h.maxTests
        .map(
          (t) =>
              '${t.seconds != null ? '${t.seconds} s' : '${t.reps} reps'} on ${_shortDay(t.date)}',
        )
        .join(', ');
    b.write(' Max tests: $tests.');
  }
  return b.toString();
}

/// An exercise's strength over time: a line of per-day bests with value labels on the axis, max
/// tests ringed, and the note on what the number is. Under two days of sets it shows an empty
/// state instead of a line.
class StrengthChart extends StatelessWidget {
  const StrengthChart({super.key, required this.history, required this.units});

  final ExerciseHistory history;
  final Units units;

  static const _plotHeight = 132.0;
  static const _axisWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final h = history;
    final metric = h.metric;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              h.estimated ? '${metricTitle(metric)} (estimated)' : metricTitle(metric),
              style: AppText.label,
            ),
          ),
          const SizedBox(height: 10),
          if (h.points.length < 2)
            Text(
              'Your chart shows after sets on two different days.',
              style: AppText.body.copyWith(color: kInkSecondary),
            )
          else
            Semantics(
              label: chartSummary(h, units),
              image: true,
              excludeSemantics: true,
              child: _Plot(history: h, units: units),
            ),
          const SizedBox(height: 10),
          Text(metricNote(metric), style: AppText.caption.copyWith(color: kInkMuted)),
        ],
      ),
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({required this.history, required this.units});

  final ExerciseHistory history;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final h = history;
    final marksTests = h.metric == ChartMetric.reps || h.metric == ChartMetric.seconds;
    final tests = marksTests
        ? h.maxTests.where((t) => t.value != null).toList()
        : const <ChartMaxTest>[];
    final scale = _Scale.of(h.points, tests);
    final caption = AppText.caption.copyWith(color: kInkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: StrengthChart._plotHeight,
          child: Row(
            children: [
              SizedBox(
                width: StrengthChart._axisWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_axisValue(h.metric, scale.hi, units), style: caption),
                    Text(_axisValue(h.metric, scale.lo, units), style: caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomPaint(
                  painter: _StrengthChartPainter(
                    points: h.points,
                    maxTests: tests,
                    scale: scale,
                    color: context.accent,
                    surface: kSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: StrengthChart._axisWidth + 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_shortDay(h.points.first.date), style: caption),
              Text(_shortDay(h.points.last.date), style: caption),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Axis in ${_axisUnit(h.metric, units)}.${tests.isEmpty ? '' : ' Rings mark max tests.'}',
          style: caption,
        ),
      ],
    );
  }
}

/// The value range and date range a chart is drawn over.
class _Scale {
  const _Scale(this.lo, this.hi, this.start, this.end);

  factory _Scale.of(List<ChartPoint> points, List<ChartMaxTest> tests) {
    final values = [...points.map((p) => p.value), ...tests.map((t) => t.value!)];
    final days = [
      ...points.map((p) => p.date),
      ...tests.map((t) => t.date),
    ].map(parseLocalDate).toList()..sort();
    return _Scale(values.reduce(math.min), values.reduce(math.max), days.first, days.last);
  }

  final double lo;
  final double hi;
  final DateTime start;
  final DateTime end;
}

class _StrengthChartPainter extends CustomPainter {
  const _StrengthChartPainter({
    required this.points,
    required this.maxTests,
    required this.scale,
    required this.color,
    required this.surface,
  });

  final List<ChartPoint> points;
  final List<ChartMaxTest> maxTests;
  final _Scale scale;
  final Color color;
  final Color surface;

  static const _pad = 8.0;

  Offset _at(String date, double value, Size size) {
    final span = scale.end.difference(scale.start).inDays;
    final x = span == 0
        ? size.width / 2
        : (size.width - _pad * 2) * parseLocalDate(date).difference(scale.start).inDays / span +
              _pad;
    final range = scale.hi - scale.lo;
    final y = range == 0
        ? size.height / 2
        : _pad + (size.height - _pad * 2) * (1 - (value - scale.lo) / range);
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = kBorder
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, _pad), Offset(size.width, _pad), grid);
    canvas.drawLine(Offset(0, size.height - _pad), Offset(size.width, size.height - _pad), grid);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final dots = [for (final p in points) _at(p.date, p.value, size)];
    for (final (i, o) in dots.indexed) {
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);
    final fill = Paint()..color = color;
    for (final o in dots) {
      canvas.drawCircle(o, 3.5, fill);
    }
    final ring = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final t in maxTests) {
      final o = _at(t.date, t.value!, size);
      canvas.drawCircle(o, 8, Paint()..color = surface);
      canvas.drawCircle(o, 8, ring);
    }
  }

  @override
  bool shouldRepaint(_StrengthChartPainter old) =>
      old.points != points || old.maxTests != maxTests || old.color != color;
}
