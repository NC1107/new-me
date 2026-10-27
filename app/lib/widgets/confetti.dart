import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/accent.dart';

/// A lightweight confetti burst. Place it in a Stack over the content; it ignores pointers and
/// paints nothing when animations are disabled. Bumping [burst] plays it again.
class Confetti extends StatefulWidget {
  const Confetti({
    super.key,
    this.burst = 0,
    this.origin = const Alignment(0, -0.2),
    this.colors,
    this.particles = 70,
    this.duration = const Duration(milliseconds: 1800),
    this.spread = 1.0,
    this.autoplay = true,
  });

  /// Changes to this value start a new burst.
  final int burst;

  /// Where the burst starts within the widget's box.
  final Alignment origin;
  final List<Color>? colors;
  final int particles;
  final Duration duration;

  /// 1.0 fills a phone screen; a small card burst uses about 0.4.
  final double spread;

  /// Plays once when first built.
  final bool autoplay;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late List<_Piece> _pieces = _spawn();

  List<_Piece> _spawn() {
    final rng = math.Random(widget.burst * 7919 + 17);
    final colors = widget.colors ?? [for (final p in kAccentPresets) p.fill];
    return [
      for (var i = 0; i < widget.particles; i++)
        _Piece(
          angle: -math.pi / 2 + (rng.nextDouble() - 0.5) * math.pi * 1.5,
          speed: 0.45 + rng.nextDouble() * 0.75,
          size: 6 + rng.nextDouble() * 6,
          spin: (rng.nextDouble() - 0.5) * 14,
          phase: rng.nextDouble() * math.pi * 2,
          color: colors[rng.nextInt(colors.length)],
          round: rng.nextBool(),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(Confetti old) {
    super.didUpdateWidget(old);
    if (old.burst != widget.burst) {
      _pieces = _spawn();
      _play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _controller.isAnimating
              ? CustomPaint(
                  size: Size.infinite,
                  painter: _ConfettiPainter(
                    pieces: _pieces,
                    t: _controller.value,
                    origin: widget.origin,
                    spread: widget.spread,
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.phase,
    required this.color,
    required this.round,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final double phase;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.pieces,
    required this.t,
    required this.origin,
    required this.spread,
  });

  final List<_Piece> pieces;
  final double t;
  final Alignment origin;
  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    final start = origin.alongSize(size);
    final reach = size.shortestSide * 1.1 * spread;
    final fall = size.shortestSide * 0.9 * spread;
    final eased = Curves.easeOutCubic.transform(t);
    for (final p in pieces) {
      final x = start.dx + math.cos(p.angle) * p.speed * reach * eased;
      final y = start.dy + math.sin(p.angle) * p.speed * reach * eased + fall * t * t;
      final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
