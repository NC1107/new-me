import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import 'streak_visuals.dart';

/// Under the day card: a "Can't today?" link that opens the Away page, or, while the person is
/// away, a card saying so. Either way it is one tap to the same page.
class AwayLine extends StatelessWidget {
  const AwayLine({super.key, required this.away, required this.onOpen});

  final AwayState away;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final span = away.current;
    if (away.today) {
      final until = span == null ? null : DateFormat('E d MMM').format(parseLocalDate(span.to));
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: "Can't today? Set away days",
        excludeSemantics: true,
        onTap: onOpen,
        child: Pressable(
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_outline_rounded, size: 20, color: kInkSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "Can't today?",
                    style: AppText.label.copyWith(
                      color: kInkSecondary,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
