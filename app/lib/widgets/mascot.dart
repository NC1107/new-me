import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

enum MascotState { idle, happy, cheer, sleepy, sad, thinking }

/// The New Me mascot: a ring body in the person's colour (the app icon's ring), a pale face,
/// eyes with highlights and a mouth. Decorative, so hidden from screen readers.
///
/// Idle, happy and thinking blink every few seconds; cheer hops. Each is a short one-off
/// animation scheduled by a timer, so a screen holding a mascot still settles in tests.
/// Nothing moves when [MediaQuery.disableAnimations] is set.
class Mascot extends StatefulWidget {
  const Mascot({super.key, this.size = 96, this.state = MascotState.idle, this.palette});

  final double size;
  final MascotState state;

  /// Turns off the periodic blink and hop. Widget tests that call pumpAndSettle set this to
  /// false, because a timer that always rearms never lets the tree settle.
  static bool idleMotion = true;

  /// The body colour; the person's colour from the theme when null.
  final AccentPalette? palette;

  @override
  State<Mascot> createState() => _MascotState();
}

enum _Move { blink, hop, react }

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  Timer? _timer;
  _Move _move = _Move.blink;
  bool _reduce = false;

  AccentPalette _palette(BuildContext context) => widget.palette ?? context.accentPalette;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduce || _timer == null) {
      _reduce = reduce;
      _restart();
    }
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _restart();
      if (!_reduce) _play(_Move.react, const Duration(milliseconds: 420));
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (_reduce || !Mascot.idleMotion) {
      _controller.value = 0;
      return;
    }
    _schedule();
  }

  void _schedule() {
    final cheer = widget.state == MascotState.cheer;
    if (widget.state == MascotState.sleepy || widget.state == MascotState.sad) return;
    _timer = Timer(Duration(milliseconds: cheer ? 500 : 3200), () {
      if (!mounted) return;
      _play(cheer ? _Move.hop : _Move.blink, Duration(milliseconds: cheer ? 900 : 200));
      _schedule();
    });
  }

  void _play(_Move move, Duration duration) {
    _move = move;
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _palette(context);
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: TweenAnimationBuilder<AccentPalette>(
          tween: AccentTween(end: target),
          duration: _reduce ? Duration.zero : kMotionDuration,
          builder: (context, palette, _) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final running = _controller.isAnimating;
              return CustomPaint(
                painter: _MascotPainter(
                  palette: palette,
                  state: widget.state,
                  blink: running && _move == _Move.blink ? math.sin(math.pi * t) : 0,
                  hop: running && _move == _Move.hop ? t : 0,
                  react: running && _move == _Move.react ? math.sin(math.pi * t) : 0,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.palette,
    required this.state,
    required this.blink,
    required this.hop,
    required this.react,
  });

  final AccentPalette palette;
  final MascotState state;
  final double blink;
  final double hop;
  final double react;

  // The face is drawn in a 100 x 100 box and scaled to the widget.
  static const _cx = 50.0;
  static const _cy = 54.0;
  static const _outer = 42.0;
  static const _ring = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);

    // Two hops over the animation, each a half sine.
    final lift = hop == 0 ? 0.0 : (math.sin(hop * math.pi * 2).abs() * 12);
    final squash = 1 + react * 0.07;

    _shadow(canvas, lift);

    canvas.save();
    canvas.translate(_cx, _cy - lift);
    canvas.scale(squash, 2 - squash);
    canvas.translate(-_cx, -_cy);
    _body(canvas);
    _face(canvas);
    canvas.restore();
  }

  void _shadow(Canvas canvas, double lift) {
    final grow = 1 - lift / 40;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(_cx, 97), width: 52 * grow, height: 6 * grow),
      Paint()..color = kInk.withValues(alpha: 0.08),
    );
  }

  void _body(Canvas canvas) {
    final lip = Paint()..color = palette.lip;
    final fill = Paint()..color = palette.fill;
    canvas.drawCircle(const Offset(_cx, _cy + 4), _outer, lip);
    canvas.drawCircle(const Offset(_cx, _cy), _outer, fill);
    canvas.drawCircle(const Offset(_cx, _cy), _outer - _ring, Paint()..color = kSurface);
    // A soft inner shade at the bottom of the face gives the ring depth.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(_cx, _cy), radius: _outer - _ring - 1),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = palette.tint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(_cx, _cy), radius: _outer - _ring / 2),
      math.pi * 1.05,
      math.pi * 0.28,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
    );
  }

  Paint get _ink => Paint()..color = kInk;

  Paint get _line => Paint()
    ..color = kInk
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  void _face(Canvas canvas) {
    switch (state) {
      case MascotState.idle:
        _eyes(canvas);
        _smile(canvas, 6, 4);
      case MascotState.happy:
        _eyes(canvas);
        _cheeks(canvas);
        _smile(canvas, 9, 8);
      case MascotState.cheer:
        _happyEyes(canvas);
        _cheeks(canvas);
        _openMouth(canvas);
      case MascotState.sleepy:
        _sleepyEyes(canvas);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(_cx, _cy + 14), width: 6, height: 7),
          _line..strokeWidth = 2.4,
        );
        _zzz(canvas);
      case MascotState.sad:
        _eyes(canvas, dy: 1.5);
        _brows(canvas, sad: true);
        final p = Path()
          ..moveTo(_cx - 7, _cy + 17)
          ..quadraticBezierTo(_cx, _cy + 10, _cx + 7, _cy + 17);
        canvas.drawPath(p, _line);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(_cx + 14, _cy + 6), width: 3.6, height: 5.4),
          Paint()..color = const Color(0xFF7CC4F0),
        );
      case MascotState.thinking:
        _eyes(canvas, dx: 2.2, dy: -2);
        _curiousBrows(canvas);
        canvas.drawPath(
          Path()
            ..moveTo(_cx - 3, _cy + 14)
            ..quadraticBezierTo(_cx + 2, _cy + 12, _cx + 7, _cy + 13),
          _line,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(_cx + 30 + i * 5.0, _cy - 38 - i * 6.0),
            1.6 + i * 0.9,
            Paint()..color = kLip,
          );
        }
    }
  }

  void _eyes(Canvas canvas, {double dx = 0, double dy = 0}) {
    const w = 8.0;
    const h = 11.0;
    for (final side in [-1.0, 1.0]) {
      final c = Offset(_cx + side * 13 + dx, _cy - 4 + dy);
      final open = (1 - blink * 0.92).clamp(0.08, 1.0);
      canvas.drawOval(Rect.fromCenter(center: c, width: w, height: h * open), _ink);
      if (open > 0.5) {
        canvas.drawCircle(c.translate(1.5, -2.4 * open), 1.9, Paint()..color = Colors.white);
      }
    }
  }

  void _happyEyes(Canvas canvas) {
    for (final side in [-1.0, 1.0]) {
      final c = Offset(_cx + side * 13, _cy - 3);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 5, c.dy + 2)
          ..quadraticBezierTo(c.dx, c.dy - 7, c.dx + 5, c.dy + 2),
        _line..strokeWidth = 3.2,
      );
    }
  }

  void _sleepyEyes(Canvas canvas) {
    for (final side in [-1.0, 1.0]) {
      final c = Offset(_cx + side * 13, _cy - 3);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 5, c.dy - 1)
          ..quadraticBezierTo(c.dx, c.dy + 5, c.dx + 5, c.dy - 1),
        _line..strokeWidth = 3,
      );
    }
  }

  void _brows(Canvas canvas, {required bool sad}) {
    for (final side in [-1.0, 1.0]) {
      final x = _cx + side * 13;
      // Sad brows tilt up toward the middle.
      final inner = sad ? -4.0 : 0.0;
      const outer = 0.0;
      canvas.drawLine(
        Offset(x - side * 5, _cy - 14 + inner),
        Offset(x + side * 5, _cy - 14 + outer),
        _line..strokeWidth = 2.4,
      );
    }
  }

  /// Straight brows read as a frown at this size; soft raised arcs read as wondering.
  void _curiousBrows(Canvas canvas) {
    for (final side in [-1.0, 1.0]) {
      final x = _cx + side * 13 + 2.2;
      final y = _cy - 17 - (side > 0 ? 3.0 : 0.0);
      canvas.drawPath(
        Path()
          ..moveTo(x - 5, y + 2)
          ..quadraticBezierTo(x, y - 3, x + 5, y + 2),
        _line..strokeWidth = 2.4,
      );
    }
  }

  void _cheeks(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFF59C94).withValues(alpha: 0.5);
    canvas.drawCircle(const Offset(_cx - 22, _cy + 8), 4.2, paint);
    canvas.drawCircle(const Offset(_cx + 22, _cy + 8), 4.2, paint);
  }

  void _smile(Canvas canvas, double halfWidth, double depth) {
    canvas.drawPath(
      Path()
        ..moveTo(_cx - halfWidth, _cy + 9)
        ..quadraticBezierTo(_cx, _cy + 9 + depth * 2, _cx + halfWidth, _cy + 9),
      _line,
    );
  }

  void _openMouth(Canvas canvas) {
    final mouth = Path()
      ..moveTo(_cx - 10, _cy + 8)
      ..quadraticBezierTo(_cx, _cy + 6, _cx + 10, _cy + 8)
      ..quadraticBezierTo(_cx + 9, _cy + 23, _cx, _cy + 23)
      ..quadraticBezierTo(_cx - 9, _cy + 23, _cx - 10, _cy + 8)
      ..close();
    canvas.drawPath(mouth, _ink);
    canvas.save();
    canvas.clipPath(mouth);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(_cx, _cy + 22), width: 12, height: 10),
      Paint()..color = const Color(0xFFE5675A),
    );
    canvas.restore();
  }

  void _zzz(Canvas canvas) {
    for (var i = 0; i < 2; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            fontSize: 11 + i * 4.0,
            color: kInkMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_cx + 28 + i * 7.0, _cy - 44 - i * 9.0));
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.palette != palette ||
      old.state != state ||
      old.blink != blink ||
      old.hop != hop ||
      old.react != react;
}
