import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dismiss_x.dart';
import 'progress_logic.dart';

/// One line about the month that just ended: its best improvement for the couple, else for the
/// first person who has one.
String lookbackHeadline(Lookback lb) {
  final best =
      lb.couple.improvements.firstOrNull ?? lb.people.expand((p) => p.improvements).firstOrNull;
  if (best == null) return 'See how the month went against the one before.';
  return improvementSentence(best);
}

/// The look-back as the Today "right now" card on the 1st of the month.
class LookbackNowCard extends StatelessWidget {
  const LookbackNowCard({
    super.key,
    required this.lookback,
    required this.onTap,
    required this.onDismiss,
  });

  final Lookback lookback;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('violet');
    final headline = lookbackHeadline(lookback);
    return AppCard(
      onTap: onTap,
      semanticLabel: '${lookback.label} look-back. $headline',
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.calendar_month_rounded, size: 24, color: palette.lip),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your ${lookback.label.split(' ').first} look-back',
                    style: AppText.headline.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 2),
                  Text(headline, style: AppText.label.copyWith(color: kInkSecondary)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Open the look-back',
                            style: AppText.label.copyWith(color: context.accentText),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.accentText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DismissX(label: 'Dismiss look-back', onPressed: onDismiss),
        ],
      ),
    );
  }
}
