import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/quest_copy.dart';

/// "8,000 steps" or "7 h 30 min": a target in the unit people read it in.
String proposalValue(GoalProposal p, int value) =>
    p.unit == 'minutes' ? durationLabel(value) : '${value.formatted} ${shortUnit(p.unit)}';

/// The target the person has now, without its unit when the proposed one carries it.
String _currentValue(GoalProposal p) =>
    p.unit == 'minutes' ? durationLabel(p.current) : p.current.formatted;

/// Monday's "Goals for this week": each proposal accepts or goes away with one tap.
class GoalsCard extends StatelessWidget {
  const GoalsCard({
    super.key,
    required this.proposals,
    required this.onAccept,
    required this.onDismiss,
  });

  final List<GoalProposal> proposals;
  final ValueChanged<GoalProposal> onAccept;
  final ValueChanged<GoalProposal> onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('sky');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.flag_rounded, size: 24, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Goals for this week',
                    style: AppText.headline.copyWith(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
          for (final p in proposals) ...[
            const SizedBox(height: 14),
            _ProposalRow(proposal: p, onAccept: () => onAccept(p), onDismiss: () => onDismiss(p)),
          ],
        ],
      ),
    );
  }
}

class _ProposalRow extends StatelessWidget {
  const _ProposalRow({required this.proposal, required this.onAccept, required this.onDismiss});

  final GoalProposal proposal;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final category = questPalette(p.key);
    final proposed = proposalValue(p, p.proposed);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(kRadiusField)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(questIcon(p.key), size: 20, color: category.lip),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${p.title.isEmpty ? p.key : p.title}: ${_currentValue(p)} to $proposed',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (p.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(p.reason, style: AppText.label.copyWith(color: kInkSecondary)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _Pill(
                label: 'Accept',
                semanticLabel: 'Accept $proposed',
                filled: true,
                onTap: onAccept,
              ),
              const SizedBox(width: 8),
              _Pill(label: 'Not now', semanticLabel: 'Not now for ${p.title}', onTap: onDismiss),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: filled ? person.fill : kSurface,
              borderRadius: BorderRadius.circular(kRadiusButton),
              border: Border.all(color: filled ? person.fill : kBorder, width: kBorderWidth),
            ),
            child: Text(
              label,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w800,
                color: filled ? person.onFill : kInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
