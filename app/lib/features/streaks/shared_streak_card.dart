import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';

/// The couple's streak, the first thing on Us: days on which both counted, froze or were away,
/// with at least one of them counted.
class SharedStreakCard extends StatelessWidget {
  const SharedStreakCard({super.key, required this.streak, required this.names});

  final SharedStreak streak;

  /// Both people's names, for the sentence under the number.
  final List<String> names;

  String get _line {
    if (streak.current < 1) return 'Start a streak today';
    final pair = names.length == 2 ? '${names[0]} and ${names[1]}' : 'You both';
    return '$pair kept it going.';
  }

  @override
  Widget build(BuildContext context) {
    final days = streak.current;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Semantics(
        container: true,
        label: 'Together streak, $days ${days == 1 ? 'day' : 'days'}. Best ${streak.best}. $_line',
        excludeSemantics: true,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: Color(0xFFFFF1DE), shape: BoxShape.circle),
              child: const Icon(Icons.local_fire_department_rounded, size: 30, color: kFlame),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Together', style: AppText.caption),
                  Text(
                    days == 1 ? '1 day streak' : '${days.formatted} day streak',
                    style: AppText.tabular(AppText.title),
                  ),
                  Text(_line, style: AppText.caption.copyWith(color: kInkSecondary)),
                ],
              ),
            ),
            if (streak.best > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Best', style: AppText.caption),
                  Text(
                    streak.best.formatted,
                    style: AppText.tabular(AppText.headline.copyWith(color: kInkSecondary)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
