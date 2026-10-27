import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../streaks/streak_visuals.dart';

const _kFlameWash = Color(0xFFFFF1DE);
const _kFlameInk = Color(0xFFD9730D);

/// Seven day circles: a flame where the day counted, a snowflake where a freeze covered it, a
/// plaster where it was repaired and a pause where the person was away.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.days, required this.today, required this.todayCounted});

  final List<DayMark> days;
  final String today;

  /// Today's mark on the board can lag behind a log made a moment ago, so Today's own flag wins.
  final bool todayCounted;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('This week', style: AppText.headline)),
          const SizedBox(height: 12),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                for (final d in days)
                  Expanded(
                    child: _Day(
                      mark: d,
                      isToday: d.date == today,
                      counted: d.date == today ? todayCounted || d.counted : d.counted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.mark, required this.isToday, required this.counted});

  final DayMark mark;
  final bool isToday;
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final kind = dayStatus(mark, counted: counted);
    final weekday = weekdayShort(mark.date);
    final status = kind == DayStatus.none && isToday ? 'today' : kind.label;

    final Color fill;
    final Color border;
    final IconData? icon;
    final Color iconColor;
    if (kind == DayStatus.counted) {
      fill = _kFlameWash;
      border = kFlame;
      icon = kind.icon;
      iconColor = _kFlameInk;
    } else if (kind == DayStatus.frozen || kind == DayStatus.repaired) {
      fill = kFreezeWash;
      border = kFreezeFill;
      icon = kind.icon;
      iconColor = kFreezeText;
    } else if (kind == DayStatus.away || kind == DayStatus.rest) {
      fill = kSunken;
      border = kBorder;
      icon = kind.icon;
      iconColor = kInkSecondary;
    } else {
      fill = kSunken;
      border = isToday ? person.fill : kBorder;
      icon = null;
      iconColor = kInkMuted;
    }

    return Semantics(
      label: '$weekday, $status',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: isToday && kind == DayStatus.none ? person.fill : border,
                width: kBorderWidth,
              ),
            ),
            child: icon == null ? null : Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            weekday.substring(0, 1),
            style: AppText.caption.copyWith(
              color: isToday ? kInk : kInkMuted,
              fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
