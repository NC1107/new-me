import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'insights_logic.dart';

/// One slot of a day-by-day bar chart; a null [value] is a day with no reading.
class BarDatum {
  const BarDatum({required this.label, required this.value});

  final String label;
  final double? value;
}

/// Bars for consecutive days with an optional dashed goal line. Bars that reach the goal are solid
/// and the others are paler, so the goal reads without colour alone because the line is labelled.
/// Pressing or dragging along it reads one day out above its bar.
class DayBarChart extends StatefulWidget {
  const DayBarChart({
    super.key,
    required this.data,
    required this.color,
    required this.format,
    required this.startLabel,
    required this.endLabel,
    this.goal,
    this.goalLabel,
    this.height = 190,
  });

  final List<BarDatum> data;
  final Color color;
  final String Function(double value) format;
  final String startLabel;
  final String endLabel;
  final double? goal;
  final String? goalLabel;
  final double height;

  @override
  State<DayBarChart> createState() => _DayBarChartState();
}

class _DayBarChartState extends State<DayBarChart> {
  int? _selected;

  void _select(double dx, double width) {
    final n = widget.data.length;
    if (n == 0) return;
    final slot = ((dx - DayBarPainter.padX) / (width - DayBarPainter.padX * 2) * n).floor().clamp(
      0,
      n - 1,
    );
    if (slot == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = slot);
  }

  void _clear() {
    if (_selected != null) setState(() => _selected = null);
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
            key: ValueKey(widget.data.length),
            tween: Tween(begin: reduce ? 1 : 0, end: 1),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, reveal, _) => CustomPaint(
              size: Size(box.maxWidth, widget.height),
              painter: DayBarPainter(
                data: widget.data,
                color: widget.color,
                format: widget.format,
                startLabel: widget.startLabel,
                endLabel: widget.endLabel,
                goal: widget.goal,
                goalLabel: widget.goalLabel,
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

class DayBarPainter extends CustomPainter {
  DayBarPainter({
    required this.data,
    required this.color,
    required this.format,
    required this.startLabel,
    required this.endLabel,
    required this.goal,
    required this.goalLabel,
    required this.selected,
    required this.reveal,
    required this.textScaler,
  });

  final List<BarDatum> data;
  final Color color;
  final String Function(double value) format;
  final String startLabel;
  final String endLabel;
  final double? goal;
  final String? goalLabel;
  final int? selected;
  final double reveal;
  final TextScaler textScaler;

  static const padX = 6.0;
  static const _padTop = 30.0;
  static const _padBottom = 26.0;

  TextPainter _text(String text, {Color ink = kInkSecondary, double? maxWidth}) => TextPainter(
    text: TextSpan(
      text: text,
      style: AppText.caption.copyWith(color: ink, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
    ellipsis: '...',
  )..layout(maxWidth: maxWidth ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final plot = Rect.fromLTRB(padX, _padTop, size.width - padX, size.height - _padBottom);
    final peak = data.fold<double>(0, (m, d) => math.max(m, d.value ?? 0));
    final top = math.max(1.0, math.max(peak, goal ?? 0) * 1.1);
    double yFor(double v) => plot.bottom - v / top * plot.height * reveal;

    canvas.drawLine(
      Offset(0, plot.bottom),
      Offset(size.width, plot.bottom),
      Paint()
        ..color = kBorder
        ..strokeWidth = 2,
    );

    final slot = plot.width / data.length;
    final barWidth = math.max(3.0, slot * (data.length > 20 ? 0.62 : 0.56));
    for (var i = 0; i < data.length; i++) {
      final v = data[i].value;
      if (v == null || v <= 0) continue;
      final x = plot.left + slot * i + (slot - barWidth) / 2;
      final reached = goal == null || v >= goal!;
      final isSelected = selected == i;
      final rect = Rect.fromLTRB(x, yFor(v), x + barWidth, plot.bottom);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        ),
        Paint()..color = isSelected || reached ? color : color.withValues(alpha: 0.42),
      );
    }

    if (goal != null) {
      final y = yFor(goal!);
      final dash = Paint()
        ..color = kInk
        ..strokeWidth = 2;
      for (var x = 0.0; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, size.width), y), dash);
      }
      if (goalLabel != null && reveal >= 1) {
        final tp = _text(goalLabel!, ink: kInk, maxWidth: size.width * 0.6);
        final boxTop = math.max(0.0, y - tp.height - 6);
        Rect at(double left) => Rect.fromLTWH(left, boxTop, tp.width + 8, tp.height + 2);
        bool clear(Rect r) {
          for (var i = 0; i < data.length; i++) {
            final v = data[i].value;
            if (v == null || v <= 0) continue;
            final x = plot.left + slot * i;
            if (x + slot > r.left && x < r.right && yFor(v) < r.bottom) return false;
          }
          return true;
        }

        // The label sits over the emptier end of the line so it never hides a bar.
        final left = at(plot.left);
        final box = clear(left) ? left : at(size.width - tp.width - 10);
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(6)),
          Paint()..color = kSurface.withValues(alpha: 0.9),
        );
        tp.paint(canvas, Offset(box.left + 4, box.top + 1));
      }
    }

    final start = _text(startLabel, maxWidth: size.width / 2 - 4);
    start.paint(canvas, Offset(2, size.height - start.height - 2));
    final end = _text(endLabel, maxWidth: size.width / 2 - 4);
    end.paint(canvas, Offset(size.width - end.width - 2, size.height - end.height - 2));

    final pick = selected;
    if (pick != null && data[pick].value != null && reveal >= 1) {
      final v = data[pick].value!;
      final cx = plot.left + slot * pick + slot / 2;
      final tp = _text('${data[pick].label}  ${format(v)}', ink: kInk);
      final pad = 6.0;
      final w = tp.width + pad * 2;
      final left = (cx - w / 2).clamp(0.0, size.width - w);
      final topY = math.max(0.0, yFor(v) - tp.height - 12);
      final box = Rect.fromLTWH(left, topY, w, tp.height + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(8)),
        Paint()..color = kSurface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(8)),
        Paint()
          ..color = kBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      tp.paint(canvas, Offset(left + pad, topY + 3));
    }
  }

  @override
  bool shouldRepaint(DayBarPainter old) =>
      old.data != data ||
      old.color != color ||
      old.goal != goal ||
      old.selected != selected ||
      old.reveal != reveal ||
      old.textScaler != textScaler;
}

const _stageColors = {
  SleepStage.deep: Color(0xFF5F51B5),
  SleepStage.core: Color(0xFF7B6CD9),
  SleepStage.rem: Color(0xFF3D8FD6),
  SleepStage.awake: Color(0xFFBF7A17),
};

Color sleepStageColor(SleepStage s) => _stageColors[s]!;

/// A single rounded bar split into sleep stages with 2px gaps between them.
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.minutes, this.height = 16});

  /// Minutes per stage, in [SleepStage] order.
  final Map<SleepStage, int> minutes;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _StageBarPainter(minutes)),
  );
}

class _StageBarPainter extends CustomPainter {
  const _StageBarPainter(this.minutes);

  final Map<SleepStage, int> minutes;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = [
      for (final s in SleepStage.values)
        if ((minutes[s] ?? 0) > 0) s,
    ];
    final total = shown.fold<int>(0, (a, s) => a + minutes[s]!);
    final radius = Radius.circular(size.height / 2);
    final clip = RRect.fromRectAndRadius(Offset.zero & size, radius);
    if (total == 0) {
      canvas.drawRRect(clip, Paint()..color = kSunken);
      return;
    }
    canvas.clipRRect(clip);
    final usable = size.width - _gap * (shown.length - 1);
    var x = 0.0;
    for (final s in shown) {
      final w = usable * minutes[s]! / total;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), Paint()..color = _stageColors[s]!);
      x += w + _gap;
    }
  }

  @override
  bool shouldRepaint(_StageBarPainter old) => old.minutes != minutes;
}

/// A horizontal progress-style bar filled to [fraction] of the track.
class RankedBar extends StatelessWidget {
  const RankedBar({super.key, required this.fraction, required this.color, this.height = 12});

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final f = fraction.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? f : 0, end: f),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(painter: _RankedBarPainter(value, color)),
      ),
    );
  }
}

class _RankedBarPainter extends CustomPainter {
  const _RankedBarPainter(this.fraction, this.color);

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = kSunken);
    if (fraction <= 0) return;
    final w = math.max(size.height, size.width * fraction);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RankedBarPainter old) => old.fraction != fraction || old.color != color;
}
