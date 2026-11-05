import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/time_format.dart';
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
    return 'Streak counted today. Extra gems still earn a bonus.';
  }
  if (oneQuestAway(day, quests)) return 'One more and you count today.';
  if (streak.current < 1) return 'Reach the flag to start a streak.';
  const base = 'Reach the flag to keep your streak.';
  return streak.restAvailable && streak.restUsedOn == null
      ? '$base A freeze is ready if you need it.'
      : base;
}

/// What to do first while nothing is earned yet: the plan's first open item, or null once the
/// day has any progress or the plan has nothing left to do.
String? firstStepOf(DayScore day, Plan? plan) {
  if (day.basePoints > 0 || day.counted || plan == null) return null;
  for (final item in plan.items) {
    if (item.kind == PlanItemKind.todo) return item.text.replaceAll(RegExp(r'\.$'), '');
  }
  return null;
}

/// One line about yesterday for the top of the day: counted, covered by a freeze, repairable
/// until a time, or missed. Null when the board has no mark for that date.
String? yesterdayStatusLine({
  required String localToday,
  required List<DayMark> last7,
  required Freezes freezes,
  required DateTime now,
  Repair? repair,
}) {
  final day = parseLocalDate(localToday).subtract(const Duration(days: 1));
  final date = DateFormat('yyyy-MM-dd').format(day);
  final mark = last7.where((m) => m.date == date).firstOrNull;
  if (mark == null) return null;
  final until = repair?.until;
  if (repair != null && repair.date == date && (until == null || until.isAfter(now))) {
    final by = formatClock(until?.toLocal() ?? DateTime(2000, 1, 1, 22));
    return 'Yesterday missed. You can repair it until $by.';
  }
  if (mark.counted) return 'Yesterday counted.';
  if (mark.repaired) return 'Yesterday was repaired and counts as a frozen day.';
  if (mark.frozen) {
    final left = freezes.held == 0
        ? 'no freezes left'
        : '${freezes.held} ${freezes.held == 1 ? 'freeze' : 'freezes'} left';
    return 'Yesterday missed. A freeze held your streak, $left.';
  }
  if (mark.away) return 'Yesterday was an away day.';
  if (mark.rest) return null;
  return 'Yesterday missed. Today starts a fresh streak.';
}

/// Progress through the day's gems: the gems earned of the day's maximum, a thick bar with the
/// streak line flagged on it, one plain sentence about what keeps the streak, and the way to
/// today's plan and entries. No percent, since the bar already shows it.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.day,
    required this.streak,
    required this.onEntries,
    this.onCoach,
    this.onPlan,
    this.quests = const [],
    this.yesterday,
    this.firstStep,
  });

  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final VoidCallback onEntries;

  /// Null when the server has no coach, so the mascot stays plain.
  final VoidCallback? onCoach;

  /// Opens today's plan; null when the server has none.
  final VoidCallback? onPlan;

  /// How yesterday ended, from [yesterdayStatusLine].
  final String? yesterday;

  /// The first open item of the plan, from [firstStepOf].
  final String? firstStep;

  @override
  Widget build(BuildContext context) {
    final max = day.maxBase;
    final fraction = max == 0 ? 0.0 : day.basePoints / max;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CoachMascot(happy: day.counted, onTap: onCoach),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 6,
                      children: [
                        Text(day.basePoints.formatted, style: AppText.tabular(AppText.display)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'of ${max.formatted} gems',
                            style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                          ),
                        ),
                      ],
                    ),
                    if (day.bonusPoints > 0)
                      Text(
                        '+${day.bonusPoints.formatted} bonus',
                        style: AppText.tabular(
                          AppText.label.copyWith(
                            color: context.accentText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ThickProgressBar(
            value: fraction,
            markerAt: max == 0 ? null : day.goalPoints / max,
            markerLabel: 'Streak at ${day.goalPoints.formatted}',
            color: context.accent,
            semanticLabel:
                'Day progress, ${day.basePoints} of $max gems, streak counts at ${day.goalPoints}',
          ),
          const SizedBox(height: 10),
          if (yesterday case final line?) ...[
            Text(line, style: AppText.label.copyWith(color: kInkSecondary)),
            const SizedBox(height: 6),
          ],
          if (firstStep case final step?) ...[
            Text('First step', style: AppText.label.copyWith(color: context.accentText)),
            Text(step, style: AppText.body.copyWith(fontSize: 15)),
            const SizedBox(height: 6),
          ],
          Text(
            dayCardSentence(day, streak, quests),
            style: AppText.body.copyWith(fontSize: 15, color: kInkSecondary),
          ),
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

class _CoachMascot extends StatelessWidget {
  const _CoachMascot({required this.happy, required this.onTap});

  final bool happy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mascot = Mascot(size: 56, state: happy ? MascotState.happy : MascotState.idle);
    final tap = onTap;
    if (tap == null) return mascot;
    final palette = accentById('violet');
    return Semantics(
      container: true,
      button: true,
      label: 'Ask your coach',
      excludeSemantics: true,
      onTap: tap,
      child: Pressable(
        onTap: tap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            mascot,
            Positioned(
              right: -4,
              bottom: -2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: palette.tint,
                  shape: BoxShape.circle,
                  border: Border.all(color: kSurface, width: 2),
                ),
                child: Icon(Icons.chat_bubble_rounded, size: 12, color: palette.lip),
              ),
            ),
          ],
        ),
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
