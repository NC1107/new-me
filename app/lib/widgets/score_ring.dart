import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../util/format.dart';

const kRingMotion = Duration(milliseconds: 260);

/// The day's score: an arc that fills to the day percent, a tick on the streak line, the points in
/// the middle. It sweeps only when the numbers change; [countUp] adds one sweep from zero on
/// first build, which the caller grants once per day.
class ScoreRing extends StatefulWidget {
  const ScoreRing({
    super.key,
    required this.points,
    required this.percent,
    this.threshold = 70,
    this.countUp = false,
    this.size = 216,
  });

  final int points;
  final int percent;

  /// The percent a day needs to count; the tick sits here.
  final int threshold;
  final bool countUp;
  final double size;

  @override
  State<ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<ScoreRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kRingMotion,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  late double _fromPoints = widget.countUp ? 0 : widget.points.toDouble();
  late double _fromPercent = widget.countUp ? 0 : widget.percent.toDouble();
  bool _started = false;

  double _shown(double from, int to) => from + (to - from) * _curve.value;

  double get _points => _shown(_fromPoints, widget.points);
  double get _percent => _shown(_fromPercent, widget.percent);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.countUp && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(ScoreRing old) {
    super.didUpdateWidget(old);
    if (old.points == widget.points && old.percent == widget.percent) return;
    _fromPoints = _shown(_fromPoints, old.points);
    _fromPercent = _shown(_fromPercent, old.percent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Semantics(
      label: '${widget.points} points, ${widget.percent} percent of the day',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _RingPainter(
              fraction: (_percent / 100).clamp(0.0, 1.0),
              tick: widget.threshold / 100,
              accent: accent,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(widget.size * 0.18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _points.round().formatted,
                        style: const TextStyle(
                          color: kFgPrimary,
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_percent.round()}%',
                      style: const TextStyle(
                        color: kFgSecondary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.tick, required this.accent});

  final double fraction;
  final double tick;
  final Color accent;

  static const _stroke = 14.0;
  static const _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = kBorder;
    canvas.drawCircle(center, radius, track);

    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = accent;
      canvas.drawArc(rect, _start, 2 * math.pi * fraction, false, arc);
    }

    final angle = _start + 2 * math.pi * tick;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = kFgPrimary;
    canvas.drawLine(
      center + direction * (radius - _stroke / 2 - 4),
      center + direction * (radius + _stroke / 2 + 4),
      line,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.tick != tick || old.accent != accent;
}
