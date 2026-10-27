import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

enum BubbleTail { left, top }

/// A white bubble with a 2px border and a tail, one short line from the mascot.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text, this.tail = BubbleTail.left, this.footer});

  final String text;

  /// A small line under the text, such as the way into the plan.
  final Widget? footer;

  /// Where the tail points: left for a mascot beside the bubble, top for one above it.
  final BubbleTail tail;

  static const _tail = 10.0;

  @override
  Widget build(BuildContext context) {
    final inset = tail == BubbleTail.left
        ? const EdgeInsets.fromLTRB(_tail + 16, 12, 16, 12)
        : const EdgeInsets.fromLTRB(16, _tail + 12, 16, 12);
    return CustomPaint(
      painter: _BubblePainter(tail),
      child: Padding(
        padding: inset,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
            ?footer,
          ],
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.tail);

  final BubbleTail tail;

  @override
  void paint(Canvas canvas, Size size) {
    const t = SpeechBubble._tail;
    const r = 16.0;
    final body = tail == BubbleTail.left
        ? Rect.fromLTWH(t, 0, size.width - t, size.height)
        : Rect.fromLTWH(0, t, size.width, size.height - t);
    final path = Path()..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(r)));
    final tailPath = Path();
    if (tail == BubbleTail.left) {
      final cy = size.height / 2;
      tailPath
        ..moveTo(t + 1, cy - t)
        ..lineTo(0, cy)
        ..lineTo(t + 1, cy + t);
    } else {
      const cx = 40.0;
      tailPath
        ..moveTo(cx - t, t + 1)
        ..lineTo(cx, 0)
        ..lineTo(cx + t, t + 1);
    }
    final fill = Paint()..color = kSurface;
    final stroke = Paint()
      ..color = kBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = kBorderWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    // Cover the body's border where the tail joins, then outline only the tail's two sides.
    canvas.drawPath(tailPath..close(), fill);
    final open = Path();
    if (tail == BubbleTail.left) {
      final cy = size.height / 2;
      open
        ..moveTo(t, cy - t)
        ..lineTo(0, cy)
        ..lineTo(t, cy + t);
    } else {
      const cx = 40.0;
      open
        ..moveTo(cx - t, t)
        ..lineTo(cx, 0)
        ..lineTo(cx + t, t);
    }
    canvas.drawPath(open, stroke);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tail != tail;
}
