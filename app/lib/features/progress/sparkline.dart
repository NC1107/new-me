import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// A small line over the weekly values of a metric. Missing weeks break the line. Fewer than two
/// readings is not a trend, so it says so instead of drawing a lone dot.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    required this.semanticLabel,
    this.height = 56,
  });

  final List<double?> values;
  final Color color;
  final String semanticLabel;
  final double height;

  int get _readings => values.whereType<double>().length;

  @override
  Widget build(BuildContext context) {
    if (_readings < 2) {
      return Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: const SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('A trend shows after a second week.', style: AppText.caption),
          ),
        ),
      );
    }
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: SparklinePainter(values, color)),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  const SparklinePainter(this.values, this.color);

  final List<double?> values;
  final Color color;

  static const _pad = 6.0;

  /// The points to draw, in canvas space; null where a week has no reading.
  List<Offset?> points(Size size) {
    final readings = values.whereType<double>().toList();
    if (readings.isEmpty || values.length < 2) return const [];
    final lo = readings.reduce(math.min), hi = readings.reduce(math.max);
    final span = hi - lo;
    final w = size.width - _pad * 2, h = size.height - _pad * 2;
    return [
      for (final (i, v) in values.indexed)
        v == null
            ? null
            : Offset(
                _pad + w * i / (values.length - 1),
                // A flat series sits in the middle instead of on the floor.
                span == 0 ? size.height / 2 : _pad + h * (1 - (v - lo) / span),
              ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = points(size);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = kBorder
        ..strokeWidth = 2,
    );
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? run;
    for (final p in pts) {
      if (p == null) {
        if (run != null) canvas.drawPath(run, line);
        run = null;
      } else if (run == null) {
        run = Path()..moveTo(p.dx, p.dy);
      } else {
        run.lineTo(p.dx, p.dy);
      }
    }
    if (run != null) canvas.drawPath(run, line);
    final last = pts.lastWhere((p) => p != null, orElse: () => null);
    if (last != null) {
      canvas.drawCircle(last, 5, Paint()..color = kSurface);
      canvas.drawCircle(
        last,
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) => old.values != values || old.color != color;
}
