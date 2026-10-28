import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/thick_progress_bar.dart';

/// True when finishing any one open quest would be enough to count the day.
bool oneQuestAway(DayScore day, List<Quest> quests) {
  if (day.counted || day.maxBase == 0) return false;
  final needed = (day.streakLine * day.maxBase / 100).ceil() - day.basePoints;
  if (needed <= 0) return false;
  return quests.any((q) => !q.done && q.points - q.basePoints >= needed);
}

/// The one plain sentence under the bar. It starts a streak instead of threatening one, since a
/// fresh morning at 0% is not a test already failed.
String dayCardSentence(DayScore day, Streak streak, List<Quest> quests) {
  if (day.counted) {
    return 'Goal reached. Anything extra still earns bonus points.';
  }
  if (oneQuestAway(day, quests)) return 'One more and you count today.';
  if (streak.current < 1) return 'Reach 100% today to start your streak.';
  final base = 'Reach 100% to keep your streak going.';
  return streak.restAvailable && streak.restUsedOn == null
      ? '$base A freeze is ready if you need it.'
      : base;
}

/// Progress towards the day's goal: a thick bar that is full at the goal with any extra shown
/// as a bonus segment, the points, and one plain sentence about what keeps the streak.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.day,
    required this.streak,
    required this.onEntries,
    this.quests = const [],
  });

  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final VoidCallback onEntries;

  int get bonusPercent => math.max(0, day.goalPercent - 100);

  String get _sentence => dayCardSentence(day, streak, quests);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${day.goalPercent}%', style: AppText.tabular(AppText.display)),
              if (bonusPercent > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '+$bonusPercent% bonus',
                  style: AppText.tabular(
                    AppText.label.copyWith(color: context.accentText, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${day.basePoints.formatted} of ${day.goalPoints.formatted} points',
                  textAlign: TextAlign.end,
                  style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ThickProgressBar(
            value: bonusPercent > 0 ? 100 / day.goalPercent : day.goalPercent / 100,
            bonusValue: bonusPercent > 0 ? bonusPercent / day.goalPercent : 0,
            color: context.accent,
            semanticLabel: 'Day progress toward the goal',
          ),
          const SizedBox(height: 10),
          Text(_sentence, style: AppText.body.copyWith(fontSize: 15, color: kInkSecondary)),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            button: true,
            label: "See today's entries",
            excludeSemantics: true,
            onTap: onEntries,
            child: Pressable(
              onTap: onEntries,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'What I logged today',
                        style: AppText.label.copyWith(color: context.accentText),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.accentText),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
