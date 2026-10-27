import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

/// A 16 tall rounded bar with a lighter highlight stripe along the top third.
/// The fill eases to a new value; the first build shows its value without animating unless
/// [animateFromZero] is set. [markerAt] draws a flag on the track, like the 70% streak line.
class ThickProgressBar extends StatelessWidget {
  const ThickProgressBar({
    super.key,
    required this.value,
    this.color,
    this.markerAt,
    this.animateFromZero = false,
    this.semanticLabel,
  });

  static const barHeight = 16.0;
  static const markerHeadroom = 20.0;

  /// 0 to 1; clamped.
  final double value;

  /// The fill colour; the person's colour when null.
  final Color? color;

  /// A fraction of the track in 0..1 where a flag is planted.
  final double? markerAt;
  final bool animateFromZero;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.accent;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400);
    final marker = markerAt?.clamp(0.0, 1.0);
    final top = marker == null ? 0.0 : markerHeadroom;

    return Semantics(
      label: semanticLabel,
      value: semanticLabel == null ? null : '${(target * 100).round()}%',
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        height: barHeight + top,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: top,
                  height: barHeight,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: animateFromZero ? 0 : null, end: target),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CustomPaint(painter: _BarPainter(v, fill)),
                  ),
                ),
                if (marker != null)
                  Positioned(
                    left: (width * marker - 1).clamp(0.0, width - 2),
                    top: 0,
                    child: ExcludeSemantics(
                      child: _Flag(color: target >= marker ? fill : kInkMuted),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 2,
    height: ThickProgressBar.markerHeadroom + ThickProgressBar.barHeight,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
          ),
        ),
        Positioned(left: 2, top: -1, child: Icon(Icons.flag_rounded, size: 16, color: color)),
      ],
    ),
  );
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.value, this.fill);

  final double value;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    canvas.drawRRect(track, Paint()..color = kSunken);
    if (value <= 0) return;
    // Never narrower than the bar is tall, so a sliver still reads as a rounded pill.
    final w = (size.width * value).clamp(size.height, size.width);
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), Radius.circular(r));
    canvas.drawRRect(bar, Paint()..color = fill);
    if (w > size.height) {
      final stripe = RRect.fromRectAndRadius(
        Rect.fromLTWH(r * 0.7, size.height * 0.2, w - r * 1.4, size.height * 0.26),
        Radius.circular(size.height * 0.13),
      );
      canvas.drawRRect(stripe, Paint()..color = Colors.white.withValues(alpha: 0.32));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value || old.fill != fill;
}
