import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/mascot.dart';
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
    return 'Goal reached. Anything extra still earns bonus gems.';
  }
  if (oneQuestAway(day, quests)) return 'One more and you count today.';
  if (streak.current < 1) return 'Fill the bar today to start your streak.';
  final base = 'Fill the bar to keep your streak going.';
  return streak.restAvailable && streak.restUsedOn == null
      ? '$base A freeze is ready if you need it.'
      : base;
}

/// Progress towards the day's goal: the mascot, a thick bar that is full at the goal with any
/// extra shown as a bonus segment, the points, one plain sentence about what keeps the streak,
/// and the way to today's plan and entries.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.day,
    required this.streak,
    required this.onEntries,
    this.onPlan,
    this.quests = const [],
  });

  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final VoidCallback onEntries;

  /// Opens today's plan; null when the server has none.
  final VoidCallback? onPlan;

  int get bonusPercent => math.max(0, day.goalPercent - 100);

  String get _sentence => dayCardSentence(day, streak, quests);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Mascot(size: 56, state: day.counted ? MascotState.happy : MascotState.idle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text('${day.goalPercent}%', style: AppText.tabular(AppText.display)),
                        if (bonusPercent > 0)
                          Text(
                            '+$bonusPercent% bonus',
                            style: AppText.tabular(
                              AppText.label.copyWith(
                                color: context.accentText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '${day.basePoints.formatted} of ${day.goalPoints.formatted} gems',
                      style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ThickProgressBar(
            value: bonusPercent > 0 ? 100 / day.goalPercent : day.goalPercent / 100,
            bonusValue: bonusPercent > 0 ? bonusPercent / day.goalPercent : 0,
            color: context.accent,
            semanticLabel: 'Day progress toward the goal',
          ),
          const SizedBox(height: 10),
          Text(_sentence, style: AppText.body.copyWith(fontSize: 15, color: kInkSecondary)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (onPlan case final plan?) ...[
                Expanded(
                  child: _Link(label: "Today's plan", spoken: "Open today's plan", onTap: plan),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _Link(
                  label: 'What I logged',
                  spoken: "See today's entries",
                  onTap: onEntries,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.spoken, required this.onTap});

  final String label;
  final String spoken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: spoken,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: context.accentText),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.accentText),
          ],
        ),
      ),
    ),
  );
}
