import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../board/person_card.dart' show kSuccessText;
import 'together_bar.dart';

/// Points each person gets when the week's challenge completes (the server's rule).
const kChallengeBonus = 50;

String challengeUnit(String kind) => switch (kind) {
  'steps' => 'steps',
  'workouts' => 'workouts',
  'counted_days' => 'days',
  'reading' => 'min',
  _ => '',
};

IconData challengeIcon(String kind) => switch (kind) {
  'steps' => questIcon('steps'),
  'workouts' => Icons.fitness_center_rounded,
  'counted_days' => Icons.local_fire_department_rounded,
  'reading' => questIcon('reading'),
  _ => Icons.flag_rounded,
};

AccentPalette challengePalette(String kind) => switch (kind) {
  'steps' => accentById('sky'),
  'workouts' => accentById('violet'),
  'counted_days' => accentById('amber'),
  'reading' => accentById('teal'),
  _ => accentById('sky'),
};

/// "42,300 of 70,000 steps"
String challengeProgressText(Challenge c) {
  final unit = challengeUnit(c.kind);
  return '${c.progress.formatted} of ${c.target.formatted}${unit.isEmpty ? '' : ' $unit'}';
}

/// "3 days left", counting today; "Last day" on the final day and null once it has passed.
String? challengeDaysLeft(Challenge c, String today) {
  if (c.endsOn.isEmpty || today.isEmpty) return null;
  final left = parseLocalDate(c.endsOn).difference(parseLocalDate(today)).inDays + 1;
  if (left < 1) return null;
  return left == 1 ? 'Last day' : '$left days left';
}

/// The week's shared challenge on Us. One bar for both of you, since the server only reports the
/// combined number.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.today,
    required this.people,
  });

  final Challenge challenge;
  final String today;

  /// The two people's colours, for the bar.
  final List<AccentPalette> people;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final palette = challengePalette(c.kind);
    final left = c.done ? null : challengeDaysLeft(c, today);
    final from = people.isNotEmpty ? people.first.fill : palette.fill;
    final to = people.length > 1 ? people[1].fill : from;
    return AppCard(
      borderColor: c.done ? Color.lerp(kBorder, kSuccess, 0.6)! : kBorder,
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IconBubble(
                  icon: c.done ? Icons.emoji_events_rounded : challengeIcon(c.kind),
                  palette: palette,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Weekly challenge', style: AppText.caption),
                      Text(c.title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TogetherBar(value: c.done ? 1 : c.fraction, from: from, to: to),
            const SizedBox(height: 10),
            if (c.done)
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 20, color: kSuccess),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Done! +$kChallengeBonus points each',
                      style: AppText.label.copyWith(
                        color: kSuccessText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    challengeProgressText(c),
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (left != null) Text(left, style: AppText.caption),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.palette});

  final IconData icon;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
    child: Icon(icon, size: 24, color: palette.lip),
  );
}
