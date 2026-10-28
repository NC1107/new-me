import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dismiss_x.dart';
import 'recap_logic.dart';

/// The recap as the Today "right now" card: one line about the week and a way in.
class RecapNowCard extends StatelessWidget {
  const RecapNowCard({
    super.key,
    required this.recap,
    required this.onTap,
    required this.onDismiss,
  });

  final Recap recap;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('violet');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Weekly recap. ${recapHeadline(recap)}',
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
              child: Icon(Icons.insights_rounded, size: 24, color: palette.lip),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            // The card's label reads this text, so it is not read a second time.
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recap.complete ? 'Your week is in' : 'Your week so far',
                      style: AppText.headline.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(recapHeadline(recap), style: AppText.label.copyWith(color: kInkSecondary)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Open the recap',
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
          ),
          DismissX(label: 'Dismiss recap', onPressed: onDismiss),
        ],
      ),
    );
  }
}
