import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/time_format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/thick_progress_bar.dart';
import 'streak_visuals.dart';

/// "Tuesday" for a yyyy-MM-dd date.
String weekdayLong(String date) => DateFormat.EEEE().format(parseLocalDate(date));

/// The words of the repair card, apart from the widget so they can be tested.
({String title, String body}) repairCopy(Repair repair, int percent) {
  final day = weekdayLong(repair.date);
  if (percent >= 100) {
    return (title: 'Yesterday is repaired', body: '$day now counts as a frozen day.');
  }
  final until = repair.until == null ? '22:00' : formatClock(repair.until!.toLocal());
  return (
    title: 'Repair yesterday',
    body: 'You missed $day. Reach 100% today before $until and it counts as a frozen day.',
  );
}

/// Shown in the right-now slot while yesterday is a missed, unfrozen day and the window to
/// repair it is open, with today's progress toward the 100% it needs.
class RepairCard extends StatelessWidget {
  const RepairCard({super.key, required this.repair, required this.percent});

  final Repair repair;

  /// Today's progress through the day, 0 to 100.
  final int percent;

  @override
  Widget build(BuildContext context) {
    final copy = repairCopy(repair, percent);
    final done = percent >= 100;
    final shown = percent.clamp(0, 100);
    return AppCard(
      color: kFreezeWash,
      borderColor: kFreezeFill,
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: kSurface, shape: BoxShape.circle),
                  child: Icon(
                    done ? Icons.check_circle_rounded : Icons.healing_rounded,
                    size: 24,
                    color: kFreezeText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(copy.title, style: AppText.headline)),
              ],
            ),
            const SizedBox(height: 8),
            Text(copy.body, style: AppText.label.copyWith(color: kInkSecondary)),
            const SizedBox(height: 12),
            ThickProgressBar(
              value: shown / 100,
              color: kFreezeFill,
              semanticLabel: 'Progress toward repairing yesterday',
            ),
            const SizedBox(height: 6),
            Text(
              '$shown% of 100%',
              style: AppText.tabular(
                AppText.label.copyWith(color: kFreezeText, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
