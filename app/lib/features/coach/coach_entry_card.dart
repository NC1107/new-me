import 'package:flutter/material.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';

/// The coach's one front door, at the top of Insights.
class CoachEntryCard extends StatelessWidget {
  const CoachEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('violet');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Ask your coach',
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.chat_bubble_rounded, size: 22, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your coach',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    ),
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
