import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import 'streak_visuals.dart';

/// Under the day card while the person is away: a card saying so that opens the Away page. Away
/// days are set from the streak sheet otherwise.
class AwayLine extends StatelessWidget {
  const AwayLine({super.key, required this.away, required this.onOpen});

  final AwayState away;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final span = away.current;
    if (!away.today) return const SizedBox.shrink();
    final until = span == null ? null : dayWithWeekday(span.to);
    return AppCard(
      onTap: onOpen,
      semanticLabel: 'Away today${until == null ? '' : ' until $until'}, open away days',
      color: kFreezeWash,
      borderColor: kFreezeFill,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            const Icon(Icons.pause_circle_rounded, size: 26, color: kFreezeText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('You are away', style: AppText.headline),
                  Text(
                    until == null
                        ? 'Your streak is paused.'
                        : 'Your streak is paused until $until.',
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}
