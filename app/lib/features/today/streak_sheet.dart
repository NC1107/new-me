import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/thick_progress_bar.dart';
import '../streaks/streak_visuals.dart';

Future<void> showStreakSheet(
  BuildContext context, {
  required Streak streak,
  required int line,
  Freezes freezes = const Freezes(),
  VoidCallback? onAway,
}) => showAppSheet<void>(
  context,
  builder: (_) => StreakSheet(streak: streak, line: line, freezes: freezes, onAway: onAway),
);

/// How the next freeze is going: "3 of 7 counted days to your next freeze", or why it waits.
String freezeProgressLabel(Freezes f) {
  if (f.held >= kMaxFreezes) {
    return 'You hold the most you can. The next one starts after you use one.';
  }
  final left = kDaysPerFreeze - f.earnedTowardNext;
  return '${f.earnedTowardNext} of $kDaysPerFreeze counted days to your next freeze'
      ' - $left to go';
}

/// What the streak is, and how freezes, repairs and away days keep it alive.
class StreakSheet extends StatelessWidget {
  const StreakSheet({
    super.key,
    required this.streak,
    required this.line,
    this.freezes = const Freezes(),
    this.onAway,
  });

  final Streak streak;
  final int line;
  final Freezes freezes;

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
                Expanded(child: Text('Day $days', style: AppText.title)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A day counts toward your streak when you reach the streak line, $line% of the day. '
              'The streak is how many counted days you have in a row.',
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
              title: 'Earning and using freezes',
              text:
                  'You start with 2 and earn 1 more for every 7 counted days, up to 2. When you '
                  'miss a day and hold a freeze, it covers the day on its own: the streak holds, '
                  'but the day adds nothing to it.',
            ),
            const SizedBox(height: 12),
            const _Point(
              icon: Icons.healing_rounded,
              title: 'Repair',
              text:
                  'Missed yesterday with no freeze left? Until 22:00 today you can repair it by '
                  'reaching 100% of today. A repaired day counts as a frozen day.',
            ),
            const SizedBox(height: 12),
            const _Point(
              icon: Icons.pause_circle_rounded,
              title: 'Away days',
              text:
                  'Sick or travelling? Away days neither break nor extend a streak and do not '
                  'use a freeze.',
            ),
            if (onAway != null) ...[
              const SizedBox(height: 16),
              ChunkyButton.secondary(
                label: "Can't today?",
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
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 24, color: kFreezeText),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              text,
              style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}
