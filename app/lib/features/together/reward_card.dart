import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import 'together_bar.dart';

/// The focus reward on Us: an invitation to add one, the bar against the gem bank while it is
/// being earned, or the "We did it" button once the bank covers its price.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.reward,
    required this.people,
    required this.onAdd,
    required this.onClaim,
    this.claiming = false,
    this.error,
  });

  final Reward? reward;
  final List<AccentPalette> people;
  final VoidCallback onAdd;
  final VoidCallback onClaim;
  final bool claiming;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final r = reward;
    final gift = accentById('rose');
    if (r == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Bubble(icon: Icons.card_giftcard_rounded, palette: gift),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rewards', style: AppText.caption),
                      Text(
                        'Something to work toward',
                        style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Pick a reward and a price in gems. Share it and earn it together, or keep it solo '
              'and redeem it from your own gems.',
              style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              child: ChunkyButton(label: 'Add a reward', icon: Icons.add_rounded, onPressed: onAdd),
            ),
          ],
        ),
      );
    }
    final from = people.isNotEmpty ? people.first.fill : gift.fill;
    final to = people.length > 1 ? people[1].fill : from;
    final left = (r.price - r.progress).clamp(0, r.price);
    return AppCard(
      borderColor: r.ready ? Color.lerp(kBorder, kFlame, 0.7)! : kBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                _Bubble(
                  icon: r.ready ? Icons.emoji_events_rounded : Icons.card_giftcard_rounded,
                  palette: r.ready ? accentById('amber') : gift,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.ready ? 'Reward ready' : 'Shared reward', style: AppText.caption),
                      Text(r.name, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TogetherBar(value: r.fraction, from: from, to: to),
          const SizedBox(height: 10),
          if (r.ready) ...[
            Text(
              'Your bank covers ${r.price.formatted} gems. Go enjoy it.',
              style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              child: ChunkyButton(
                label: 'We did it',
                icon: Icons.celebration_rounded,
                busy: claiming,
                onPressed: onClaim,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
              ),
            ],
          ] else
            MergeSemantics(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    '${r.progress.formatted} of ${r.price.formatted} gems',
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text('${left.formatted} to go', style: AppText.caption),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.icon, required this.palette});

  final IconData icon;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
    child: Icon(icon, size: 24, color: palette.lip),
  );
}
