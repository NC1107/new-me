import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';

/// Rewards or new prices my partner proposed, one row each with Approve and Decline. Shows
/// nothing when there is nothing to answer, so Us stays quiet.
class RewardProposalsCard extends ConsumerWidget {
  const RewardProposalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final proposals = ref.watch(rewardsProvider).value?.proposalsFor(userId) ?? const <Reward>[];
    if (proposals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: kCardGap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, p) in proposals.indexed) ...[
              if (i > 0) const Divider(height: 24, thickness: 2, color: kBorder),
              _ProposalRow(key: ValueKey(p.id), reward: p),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProposalRow extends ConsumerStatefulWidget {
  const _ProposalRow({super.key, required this.reward});

  final Reward reward;

  @override
  ConsumerState<_ProposalRow> createState() => _ProposalRowState();
}

class _ProposalRowState extends ConsumerState<_ProposalRow> {
  bool? _approving;
  String? _error;

  Future<void> _answer(bool approve) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _approving = approve;
      _error = null;
    });
    try {
      await ref.read(rewardsProvider.notifier).answer(widget.reward.id, approve: approve);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _approving = null;
          _error = errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reward;
    final busy = _approving != null;
    final from = r.proposedByName.isEmpty ? 'Your partner' : r.proposedByName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: context.accentTint, shape: BoxShape.circle),
              child: Icon(Icons.card_giftcard_rounded, size: 22, color: context.accentLip),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$from wants ${r.name} for ${r.price.formatted} gems',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChunkyButton.secondary(
                label: 'Decline',
                busy: _approving == false,
                onPressed: busy ? null : () => _answer(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                label: 'Approve',
                busy: _approving == true,
                onPressed: busy ? null : () => _answer(true),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: AppText.label.copyWith(color: kDangerText)),
        ],
      ],
    );
  }
}
