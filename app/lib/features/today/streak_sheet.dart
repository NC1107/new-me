import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/time_format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/info_note.dart';
import '../../widgets/thick_progress_bar.dart';
import '../streaks/streak_visuals.dart';

/// When the repair window closes, the server's `score.RepairHour`, in the phone's clock style.
String get _repairCloses => formatClock(DateTime(2000, 1, 1, 22));

Future<void> showStreakSheet(
  BuildContext context, {
  required Streak streak,
  required int line,
  Freezes freezes = const Freezes(),
  Repair? repair,
  VoidCallback? onAway,
}) => showAppSheet<void>(
  context,
  builder: (_) =>
      StreakSheet(streak: streak, line: line, freezes: freezes, repair: repair, onAway: onAway),
);

/// How the next freeze is going: "4 more days to your next freeze", or why it waits.
String freezeProgressLabel(Freezes f) {
  if (f.held >= kMaxFreezes) {
    return 'You hold the most you can. The next one starts after you use one.';
  }
  final left = kDaysPerFreeze - f.earnedTowardNext;
  return '$left more ${left == 1 ? 'day' : 'days'} to your next freeze';
}

const _kHowStreaksWork = InfoContent(
  title: 'How streaks work',
  paragraphs: [
    'You start with 2 freezes and earn 1 more for every 7 counted days, up to 2.',
    'A freeze covers a missed day on its own. The streak holds, but the day adds nothing to it.',
    'Missed yesterday with no freeze left? Earn every gem today to repair it.',
    'A repaired day counts as a frozen day.',
    'Away days neither break nor extend a streak and do not use a freeze.',
  ],
);

/// Your streak, and the freezes, repair and away days that keep it alive.
class StreakSheet extends StatelessWidget {
  const StreakSheet({
    super.key,
    required this.streak,
    required this.line,
    this.freezes = const Freezes(),
    this.repair,
    this.onAway,
  });

  final Streak streak;
  final int line;
  final Freezes freezes;

  /// The open window to repair a missed yesterday; the repair line shows only while it is set.
  final Repair? repair;

  /// Opens the Away page; the sheet closes first.
  final VoidCallback? onAway;

  @override
  Widget build(BuildContext context) {
    final used = streak.restUsedOn;
    final days = streak.current < 1 ? 1 : streak.current;
    final body = AppText.body.copyWith(color: kInkSecondary);
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
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Your streak, day $days', style: AppText.title),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A day counts when you reach the streak line at $line% of its gems. '
              'The streak is counted days in a row.',
              style: body,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      FreezeFlakes(held: freezes.held, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            '${freezes.held} of $kMaxFreezes freezes',
                            style: AppText.headline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ThickProgressBar(
                    value: freezes.held >= kMaxFreezes
                        ? 1
                        : freezes.earnedTowardNext / kDaysPerFreeze,
                    color: kFreezeFill,
                    semanticLabel: 'Progress to the next freeze',
                  ),
                  const SizedBox(height: 8),
                  Text(freezeProgressLabel(freezes), style: AppText.caption),
                  if (used != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'A freeze covered ${weekdayShort(used)}.',
                      style: AppText.label.copyWith(color: kFreezeText),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _Point(
              icon: Icons.ac_unit_rounded,
              text: 'Freezes save a missed day. You earn one every 7 counted days, up to 2.',
            ),
            if (repair != null) ...[
              const SizedBox(height: 12),
              _Point(
                icon: Icons.healing_rounded,
                text: 'Missed yesterday? Earn every gem today before $_repairCloses to repair it.',
              ),
            ],
            const SizedBox(height: 12),
            const _Point(
              icon: Icons.pause_circle_rounded,
              text: 'Sick or away? Away days pause your streak.',
            ),
            const InfoNote('How streaks work', info: _kHowStreaksWork),
            if (onAway != null) ...[
              const SizedBox(height: 8),
              ChunkyButton.secondary(
                label: 'Away today',
                icon: Icons.pause_circle_outline_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  onAway!();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 24, color: kFreezeText),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
