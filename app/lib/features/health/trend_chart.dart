import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';

/// One day of a metric, with its position along the window in 0..1.
class ChartPoint {
  const ChartPoint({required this.date, required this.value, required this.x});

  final String date;
  final double value;
  final double x;
}

/// Places [points] along a window of [days] days that ends on the newest point, so a gap in the
/// readings shows as a gap instead of squeezing the days together.
List<ChartPoint> placeOnWindow(List<HealthTrendPoint> points, int days) {
  if (points.isEmpty) return const [];
  final end = parseLocalDate(points.last.date);
  final span = math.max(1, days - 1);
  final out = <ChartPoint>[];
  for (final p in points) {
    final offset = end.difference(parseLocalDate(p.date)).inDays;
    if (offset < 0 || offset > span) continue;
    out.add(ChartPoint(date: p.date, value: p.value.toDouble(), x: 1 - offset / span));
  }
  return out;
}

/// A line with a soft fill under it, drawn with a [CustomPainter]. Dragging a finger along it
/// reports the nearest reading through [onSelect]; letting go reports null.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.color,
    required this.format,
    required this.onSelect,
    this.height = 220,
  });

  final List<ChartPoint> points;
  final Color color;
  final String Function(num value) format;
  final ValueChanged<int?> onSelect;
  final double height;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;

  void _select(double dx, double width) {
    if (widget.points.isEmpty) return;
    final x = (dx / width).clamp(0.0, 1.0);
    var best = 0;
    for (var i = 1; i < widget.points.length; i++) {
      if ((widget.points[i].x - x).abs() < (widget.points[best].x - x).abs()) best = i;
    }
    if (best == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = best);
    widget.onSelect(best);
  }

  void _clear() {
    if (_selected == null) return;
    setState(() => _selected = null);
    widget.onSelect(null);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _select(d.localPosition.dx, box.maxWidth),
          onTapUp: (_) => _clear(),
          onTapCancel: _clear,
          onHorizontalDragStart: (d) => _select(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) => _select(d.localPosition.dx, box.maxWidth),
          onHorizontalDragEnd: (_) => _clear(),
          onHorizontalDragCancel: _clear,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.points.length),
            tween: Tween(begin: reduce ? 1 : 0, end: 1),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, reveal, _) => CustomPaint(
              size: Size(box.maxWidth, widget.height),
              painter: TrendChartPainter(
                points: widget.points,
                color: widget.color,
                format: widget.format,
                selected: _selected,
                reveal: reveal,
                textScaler: scaler,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrendChartPainter extends CustomPainter {
  TrendChartPainter({
    required this.points,
    required this.color,
    required this.format,
    required this.selected,
    required this.reveal,
    required this.textScaler,
  });

  final List<ChartPoint> points;
  final Color color;
  final String Function(num value) format;
  final int? selected;
  final double reveal;
  final TextScaler textScaler;

  static const _padTop = 30.0;
  static const _padBottom = 26.0;
  static const _padX = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plot = Rect.fromLTRB(_padX, _padTop, size.width - _padX, size.height - _padBottom);

    final values = points.map((p) => p.value);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final pad = hi == lo ? math.max(1.0, hi.abs() * 0.1) : (hi - lo) * 0.12;
    final minY = lo - pad;
    final maxY = hi + pad;

    Offset at(ChartPoint p) => Offset(
      plot.left + p.x * plot.width,
      plot.bottom - (p.value - minY) / (maxY - minY) * plot.height,
    );

    final grid = Paint()
      ..color = kBorder
      ..strokeWidth = 1.5;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = plot.top + plot.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final offsets = [for (final p in points) at(p)];

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));

    if (offsets.length == 1) {
      canvas.drawCircle(offsets.first, 6, Paint()..color = color);
    } else {
      final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (var i = 1; i < offsets.length; i++) {
        final a = offsets[i - 1];
        final b = offsets[i];
        final mid = (a.dx + b.dx) / 2;
        line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      }
      final fill = Path.from(line)
        ..lineTo(offsets.last.dx, plot.bottom)
        ..lineTo(offsets.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    final minAt = points.indexOf(points.reduce((a, b) => b.value < a.value ? b : a));
    final maxAt = points.indexOf(points.reduce((a, b) => b.value > a.value ? b : a));
    if (reveal >= 1 && hi != lo) {
      _label(canvas, size, offsets[maxAt], format(hi), above: true);
      _label(canvas, size, offsets[minAt], format(lo), above: false);
    }

    final shown = selected ?? points.length - 1;
    final dot = offsets[shown];
    if (selected != null) {
      canvas.drawLine(
        Offset(dot.dx, plot.top - 6),
        Offset(dot.dx, plot.bottom),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 2,
      );
    }
    if (reveal >= 1) {
      canvas.drawCircle(dot, 9, Paint()..color = kSurface);
      canvas.drawCircle(dot, 6, Paint()..color = color);
    }
  }

  void _label(Canvas canvas, Size size, Offset anchor, String text, {required bool above}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.caption.copyWith(color: kInkSecondary, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final x = (anchor.dx - tp.width / 2).clamp(2.0, size.width - tp.width - 2);
    final y = above ? anchor.dy - tp.height - 8 : anchor.dy + 8;
    tp.paint(canvas, Offset(x, y.clamp(0.0, size.height - tp.height)));
  }

  @override
  bool shouldRepaint(TrendChartPainter old) =>
      old.points != points ||
      old.color != color ||
      old.selected != selected ||
      old.reveal != reveal ||
      old.textScaler != textScaler;
}
