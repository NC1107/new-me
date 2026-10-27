import 'package:flutter/material.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';

/// The row on Us (and Insights) that opens Progress.
class ProgressEntryCard extends StatelessWidget {
  const ProgressEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('teal');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Progress, months of change, you and your partner',
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      // The label already says what the text says, so the text is not read a second time.
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.show_chart_rounded, size: 24, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Progress', style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    const Text('Months of change, you and your partner', style: AppText.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kInkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
