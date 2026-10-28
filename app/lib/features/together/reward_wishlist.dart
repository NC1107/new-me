import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';

/// The wishlist under the focus bar: approved rewards waiting their turn, my own proposals that
/// wait for an answer or were declined, and a row to add another. Tapping a row opens it.
class RewardWishlist extends StatelessWidget {
  const RewardWishlist({
    super.key,
    required this.rewards,
    required this.partner,
    required this.onOpen,
    required this.onAdd,
  });

  final List<Reward> rewards;
  final String? partner;
  final void Function(Reward reward) onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final r in rewards) ...[
            _WishRow(reward: r, partner: partner, onTap: () => onOpen(r)),
            const Divider(height: 2, thickness: 2, color: kBorder),
          ],
          _AddRow(onTap: onAdd),
        ],
      ),
    );
  }
}

class _WishRow extends StatelessWidget {
  const _WishRow({required this.reward, required this.partner, required this.onTap});

  final Reward reward;
  final String? partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = '${reward.price.formatted} gems';
    final (icon, color, detail) = switch (reward) {
      Reward(declined: true) => (Icons.block_rounded, kDangerText, '$price - declined'),
      Reward(pending: true) => (
        Icons.hourglass_top_rounded,
        kInkSecondary,
        '$price - waiting for ${partner ?? 'an answer'}',
      ),
      Reward(ready: true) => (Icons.emoji_events_rounded, kFlame, '$price - ready'),
      _ => (Icons.card_giftcard_rounded, kInkSecondary, price),
    };
    return Semantics(
      button: true,
      label: '${reward.name}, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 22, color: kInkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a reward',
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      scale: 0.99,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 22, color: context.accentLip),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add a reward',
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.accentLip,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
