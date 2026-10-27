import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../streaks/streak_visuals.dart';

/// The last seven dates the board knows about, oldest first.
List<String> weekDates(List<BoardUser> users) {
  final dates = {for (final u in users) ...u.last7.map((d) => d.date)}.toList()..sort();
  return dates.length > 7 ? dates.sublist(dates.length - 7) : dates;
}

/// Grouped bars, one per person per day, as a percent of the day's goal. A dashed line marks
/// where a day starts to count. Days that count are drawn in the person's full colour.
class WeekChart extends StatelessWidget {
  const WeekChart({super.key, required this.users});

  final List<BoardUser> users;

  static const _height = 150.0;

  @override
  Widget build(BuildContext context) {
    final dates = weekDates(users);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final summary = users
        .map((u) {
          final counted = u.last7.where((d) => d.counted && dates.contains(d.date)).length;
          int days(DayStatus s) =>
              u.last7.where((d) => dates.contains(d.date) && dayStatus(d) == s).length;
          final extras = [
            for (final s in [DayStatus.frozen, DayStatus.repaired, DayStatus.away])
              if (days(s) > 0) '${days(s)} ${s.label}${days(s) == 1 ? '' : 's'}',
          ];
          return '${u.name} counted $counted of ${dates.length} days'
              '${extras.isEmpty ? '' : ', ${extras.join(', ')}'}';
        })
        .join('. ');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Semantics(
        label: dates.isEmpty ? 'No days yet this week' : 'Last 7 days. $summary',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [for (final u in users) _LegendDot(user: u)],
            ),
            const SizedBox(height: 12),
            if (dates.isEmpty)
              SizedBox(
                height: _height,
                child: Center(
                  child: Text(
                    'Bars appear after your first day.',
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: _height,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduce ? 1 : 0, end: 1),
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, grow, _) => CustomPaint(
                    size: const Size(double.infinity, _height),
                    painter: _BarsPainter(users: users, dates: dates, grow: grow),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final date in dates)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            weekdayShort(date).substring(0, 1),
                            style: AppText.caption.copyWith(
                              fontWeight: date == dates.last ? FontWeight.w900 : FontWeight.w700,
                              color: date == dates.last ? kInk : kInkSecondary,
                            ),
                          ),
                          _DayMarks(users: users, date: date),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_hasMarks(users, dates)) ...[const _MarksLegend(), const SizedBox(height: 6)],
              const Row(
                children: [
                  _DashSample(),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A day counts from here. Lighter bars are days still short of it.',
                      style: AppText.caption,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _hasMarks(List<BoardUser> users, List<String> dates) => users.any(
  (u) => u.last7.any(
    (d) =>
        dates.contains(d.date) &&
        dayStatus(d) != DayStatus.counted &&
        dayStatus(d) != DayStatus.none,
  ),
);

/// Under a day's letter: a small icon in each person's colour where they were frozen, away or
/// repaired that day.
class _DayMarks extends StatelessWidget {
  const _DayMarks({required this.users, required this.date});

  final List<BoardUser> users;
  final String date;

  @override
  Widget build(BuildContext context) {
    final marks = <Widget>[];
    for (final u in users) {
      final mark = u.last7.where((d) => d.date == date).firstOrNull;
      if (mark == null) continue;
      final status = dayStatus(mark);
      final icon = status.icon;
      if (icon == null || status == DayStatus.counted) continue;
      marks.add(Icon(icon, size: 14, color: accentById(u.color).lip));
    }
    if (marks.isEmpty) return const SizedBox(height: 14);
    return Row(mainAxisSize: MainAxisSize.min, children: marks);
  }
}

class _MarksLegend extends StatelessWidget {
  const _MarksLegend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 2,
    children: [
      for (final s in [DayStatus.frozen, DayStatus.repaired, DayStatus.away])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(s.icon, size: 14, color: kInkSecondary),
            const SizedBox(width: 4),
            Text(s.label.replaceAll(' day', ''), style: AppText.caption),
          ],
        ),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.user});

  final BoardUser user;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: accentById(user.color).fill, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(user.name, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
      ),
    ],
  );
}

class _DashSample extends StatelessWidget {
  const _DashSample();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 24, height: 4, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) => _dashedLine(canvas, 0, size.width, size.height / 2);

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

void _dashedLine(Canvas canvas, double x0, double x1, double y) {
  final paint = Paint()
    ..color = kInkMuted
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  for (var x = x0; x < x1; x += 7) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, x1), y), paint);
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({required this.users, required this.dates, required this.grow});

  final List<BoardUser> users;
  final List<String> dates;
  final double grow;

  static const _threshold = 70.0;
  static const _minBar = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final slots = dates.length;
    final slotW = size.width / 7;
    // Fewer than seven days still sit at the right, like the week strip they replace.
    final offset = (7 - slots) * slotW;
    final top = 4.0;
    final base = size.height;
    final usable = base - top;

    final ceiling = math.max(
      100.0,
      users.expand((u) => u.last7).fold<double>(0, (m, d) => math.max(m, d.percent.toDouble())),
    );
    double heightOf(int percent) =>
        math.max(_minBar, percent / ceiling * usable) * grow.clamp(0.0, 1.0);

    final barW = math.min(18.0, (slotW - 8) / math.max(1, users.length));
    final gap = 4.0;
    final groupW = barW * users.length + gap * (users.length - 1);

    final lineY = base - _threshold / ceiling * usable;
    _dashedLine(canvas, 0, size.width, lineY);

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = kBorder
        ..strokeWidth = 2,
    );

    for (var i = 0; i < slots; i++) {
      final left = offset + i * slotW + (slotW - groupW) / 2;
      for (var j = 0; j < users.length; j++) {
        final mark = users[j].last7.where((d) => d.date == dates[i]).firstOrNull;
        if (mark == null) continue;
        final palette = accentById(users[j].color);
        final h = heightOf(mark.percent);
        final x = left + j * (barW + gap);
        final color = mark.counted
            ? palette.fill
            : Color.alphaBlend(palette.fill.withValues(alpha: 0.45), kSurface);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, base - h - 1, barW, h),
            topLeft: const Radius.circular(7),
            topRight: const Radius.circular(7),
          ),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.users != users || old.dates != dates || old.grow != grow;
}
