import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/quest_copy.dart';

/// Quests judged on the night that ended this morning, so they are settled once the night is in.
const kOvernightQuests = {'sleep', 'sleep_regularity'};

/// Whether the night this quest judges has arrived, after which nothing today can change it.
bool nightSettled(Quest q) => switch (q.key) {
  'sleep' => q.actual > 0,
  'sleep_regularity' => q.detail?['measurable'] == true,
  _ => false,
};

/// Today's quests in the order the list shows them, and the overnight ones it leaves out.
/// A night that met its goal leads, so a good night is the first thing ticked off in the
/// morning; a night that fell short cannot be made up today, so it leaves the to-do list for a
/// note of what it earned.
({List<Quest> list, List<Quest> missed}) orderQuests(List<Quest> quests) {
  bool overnight(Quest q) => kOvernightQuests.contains(q.key);
  final missed = [
    for (final q in quests)
      if (overnight(q) && nightSettled(q) && !q.done) q,
  ];
  return (
    list: [
      for (final q in quests)
        if (overnight(q) && q.done) q,
      for (final q in quests)
        if (!(overnight(q) && q.done) && !missed.contains(q)) q,
    ],
    missed: missed,
  );
}

/// What a short night still earned, since every quest pays in proportion and only the finish
/// bonus needs the whole goal.
String lastNightGems(Quest q) =>
    q.basePoints == 0 ? 'Last night, no gems' : 'Last night, ${q.basePoints} of ${q.points} gems';

/// "5 h 34 min of 7 h 30 min" for sleep, the bedtime check's verdict for the steady bedtime.
String lastNightLine(Quest q) => switch (q.key) {
  'sleep' => 'Slept ${durationLabel(q.actual)} of ${durationLabel(q.target)}',
  _ => steadyBedtimeProgress(q),
};

/// The overnight quests last night fell short on, as a quiet note under the quests rather than
/// open cards, since nothing today can finish them.
class LastNightCard extends StatelessWidget {
  const LastNightCard({super.key, required this.missed, required this.onOpen});

  final List<Quest> missed;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: kSunken,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in missed)
            Semantics(
              button: true,
              label: '${lastNightLine(q)}. ${lastNightGems(q)}.',
              excludeSemantics: true,
              onTap: () => onOpen(q.key),
              child: Pressable(
                onTap: () => onOpen(q.key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          q.key == 'sleep' ? Icons.bedtime_rounded : Icons.alarm_on_rounded,
                          size: 22,
                          color: kInkMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lastNightLine(q),
                                style: AppText.label.copyWith(
                                  color: kInkSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(lastNightGems(q), style: AppText.caption),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: kInkMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
