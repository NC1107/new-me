import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/habit_models.dart';
import '../../state/habit_proposals.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';

/// The partner's habit gems waiting for my answer, one row each. Shows nothing when there is
/// nothing to answer, so Us stays quiet.
class HabitProposalsCard extends ConsumerWidget {
  const HabitProposalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposals = ref.watch(habitProposalsProvider).value;
    if (proposals == null || proposals.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: kCardGap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, p) in proposals.items.indexed) ...[
              if (i > 0) const Divider(height: 24, thickness: 2, color: kBorder),
              _ProposalRow(from: proposals.from, proposal: p),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProposalRow extends ConsumerStatefulWidget {
  const _ProposalRow({required this.from, required this.proposal});

  final String from;
  final HabitProposal proposal;

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
      await ref
          .read(habitProposalsProvider.notifier)
          .answer(widget.proposal.habitId, approve: approve);
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
    final busy = _approving != null;
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
              child: Icon(Icons.diamond_rounded, size: 22, color: context.accentLip),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${widget.from} wants ${widget.proposal.worth}',
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
