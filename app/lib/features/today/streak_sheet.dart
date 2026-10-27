import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dialogs.dart';

Future<void> showStreakSheet(BuildContext context, {required Streak streak, required int line}) =>
    showAppSheet<void>(
      context,
      builder: (_) => StreakSheet(streak: streak, line: line),
    );

/// What the streak is and how the rest day works.
class StreakSheet extends StatelessWidget {
  const StreakSheet({super.key, required this.streak, required this.line});

  final Streak streak;
  final int line;

  @override
  Widget build(BuildContext context) {
    final used = streak.restUsedOn;
    final status = used != null
        ? 'Rest day used ${weekdayShort(used)}'
        : streak.restAvailable
        ? 'Rest day ready'
        : 'No rest day left this week';
    final days = streak.current < 1 ? 1 : streak.current;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, size: 36, color: kFlame),
                const SizedBox(width: 8),
                Expanded(child: Text('Day $days', style: AppText.title)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A day counts toward your streak when you reach the streak line, $line% of the day. '
              'The streak is how many counted days you have in a row.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'One missed day a week is forgiven. That is your rest day: it keeps the streak but '
              'does not add to it. It only works if the day before was not also missed, and it '
              'does not carry over to the next week.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.bedtime_rounded, size: 22, color: kInkSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(status, style: AppText.label)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
