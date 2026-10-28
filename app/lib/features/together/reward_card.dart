import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import 'together_bar.dart';

/// The shared reward on Us: an invitation to start one, the bar while it is being earned, or
/// the "We did it" button once it is reached.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.reward,
    required this.people,
    required this.onStart,
    required this.onClaim,
    this.claiming = false,
    this.error,
  });

  final Reward? reward;
  final List<AccentPalette> people;
  final VoidCallback onStart;
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
                      const Text('Shared reward', style: AppText.caption),
                      Text(
                        'Earn something together',
                        style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Pick a treat and a points goal. Everything either of you earns fills the bar.',
              style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              child: ChunkyButton(
                label: 'Start a reward',
                icon: Icons.add_rounded,
                onPressed: onStart,
              ),
            ),
          ],
        ),
      );
    }
    final from = people.isNotEmpty ? people.first.fill : gift.fill;
    final to = people.length > 1 ? people[1].fill : from;
    final left = (r.target - r.progress).clamp(0, r.target);
    return AppCard(
      borderColor: r.reached ? Color.lerp(kBorder, kFlame, 0.7)! : kBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                _Bubble(
                  icon: r.reached ? Icons.emoji_events_rounded : Icons.card_giftcard_rounded,
                  palette: r.reached ? accentById('amber') : gift,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.reached ? 'Reward reached' : 'Shared reward', style: AppText.caption),
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
          if (r.reached) ...[
            Text(
              'You earned ${r.target.formatted} points together. Go enjoy it.',
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
                    '${r.progress.formatted} of ${r.target.formatted} points',
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

/// Rewards already earned, newest first, so there is a record of what you won together.
class RewardHistory extends StatelessWidget {
  const RewardHistory({super.key, required this.rewards});

  final List<Reward> rewards;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, r) in rewards.indexed) ...[
            if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
            _HistoryRow(reward: r),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.reward});

  final Reward reward;

  @override
  Widget build(BuildContext context) {
    final at = reward.claimedAt ?? reward.reachedAt;
    final when = at == null ? null : DateFormat.MMMd().format(at.toLocal());
    final detail =
        '${reward.target.formatted} points${when == null ? '' : ', ${reward.claimed ? 'enjoyed' : 'reached'} $when'}';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Semantics(
        container: true,
        label: '${reward.name}, $detail',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                reward.claimed ? Icons.check_circle_rounded : Icons.emoji_events_rounded,
                size: 22,
                color: reward.claimed ? kSuccess : kFlame,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reward.name, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
                    Text(detail, style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
