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

/// Progress towards the streak line: a thick bar with a flag at the line, the points, and one
/// plain sentence about what keeps the streak.
class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.day, required this.streak, required this.onEntries});

  final DayScore day;
  final Streak streak;
  final VoidCallback onEntries;

  String get _sentence {
    if (day.counted) {
      return 'You are past the ${day.streakLine}% line. Anything extra still earns points.';
    }
    final base = 'Reach ${day.streakLine}% to keep your streak going.';
    return streak.restAvailable && streak.restUsedOn == null
        ? '$base A rest day is ready if you need it.'
        : base;
  }

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
              Text('${day.percent}%', style: AppText.tabular(AppText.display)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${day.basePoints.formatted} of ${day.maxBase.formatted} points',
                  textAlign: TextAlign.end,
                  style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ThickProgressBar(
            value: day.percent / 100,
            markerAt: day.streakLine / 100,
            color: context.accent,
            semanticLabel: 'Day progress, streak line at ${day.streakLine} percent',
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
