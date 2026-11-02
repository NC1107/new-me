import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/coach_models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/pressable.dart';

/// Where a proposed figure came from, in the words the person reads.
String sourceLabel(String source) => switch (source) {
  'computed' => 'From your data',
  'guideline' => 'From published guidance',
  'stated' => 'Your number',
  _ => '',
};

/// A change the coach proposed, shown in the thread. Nothing is changed until Apply, and once
/// applied it says so and offers Undo.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.now,
    required this.working,
    required this.error,
    required this.onApply,
    required this.onDismiss,
    required this.onUndo,
  });

  final CoachProposal proposal;
  final DateTime now;
  final bool working;
  final String? error;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final VoidCallback onUndo;

  String get _status {
    if (proposal.pending && !now.isBefore(proposal.expiresAt)) return 'expired';
    return proposal.status;
  }

  String get _spoken {
    final lines = [for (final c in proposal.changes) '${c.label}, ${c.from} to ${c.to}'];
    return 'Suggested change: ${lines.join('. ')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final settled = status != 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.92),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
              color: status == 'applied' ? kSuccess : kBorder,
              width: kBorderWidth,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  label:
                      '$_spoken.${proposal.why.isEmpty ? '' : ' ${proposal.why}'}'
                      '${sourceLabel(proposal.source).isEmpty ? '' : ' ${sourceLabel(proposal.source)}.'}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUGGESTED CHANGE',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: kInkMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final c in proposal.changes) _ChangeRow(line: c, faded: settled),
                      if (proposal.why.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(proposal.why, style: AppText.caption.copyWith(color: kInkSecondary)),
                      ],
                      if (sourceLabel(proposal.source).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          sourceLabel(proposal.source),
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: kInkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (status == 'pending')
                  Row(
                    children: [
                      Expanded(
                        child: ChunkyButton(
                          label: 'APPLY',
                          busy: working,
                          onPressed: working ? null : onApply,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChunkyButton.secondary(
                          label: 'NOT NOW',
                          onPressed: working ? null : onDismiss,
                        ),
                      ),
                    ],
                  )
                else
                  _Settled(
                    status: status,
                    canUndo: proposal.canUndo,
                    working: working,
                    onUndo: onUndo,
                  ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(error!, style: AppText.caption.copyWith(color: kDangerText)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.line, required this.faded});

  final CoachChangeLine line;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.label, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                line.from,
                style: AppText.body.copyWith(
                  color: kInkMuted,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: kInkMuted,
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: kInkMuted),
              Text(
                line.to,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w800,
                  color: faded ? kInkSecondary : context.accentPalette.lip,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Settled extends StatelessWidget {
  const _Settled({
    required this.status,
    required this.canUndo,
    required this.working,
    required this.onUndo,
  });

  final String status;
  final bool canUndo;
  final bool working;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (status) {
      'applied' => (Icons.check_circle_rounded, 'Changed.', kSuccess),
      'undone' => (Icons.undo_rounded, 'Back to how it was.', kInkSecondary),
      'dismissed' => (Icons.remove_circle_outline_rounded, 'Not now.', kInkMuted),
      _ => (Icons.schedule_rounded, 'Expired. Ask the coach again.', kInkMuted),
    };
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: AppText.body.copyWith(fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ),
        if (status == 'applied' && canUndo)
          Semantics(
            button: true,
            label: 'Undo this change',
            excludeSemantics: true,
            onTap: working ? null : onUndo,
            child: Pressable(
              onTap: working ? null : onUndo,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
                child: Center(
                  child: Text(
                    'Undo',
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.accentPalette.lip,
                      decoration: TextDecoration.underline,
                      decorationColor: context.accentPalette.lip,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A one line note that the coach saved or forgot something about the person. Tapping it
/// opens what the coach knows.
class FactNote extends StatelessWidget {
  const FactNote({super.key, required this.action, required this.onOpen});

  final CoachAction action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final saved = action.type == 'fact_saved';
    final text = action.fact!.text;
    final label = saved ? 'Saved to your profile: $text' : 'Forgot: $text';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$label. Open what the coach knows',
        excludeSemantics: true,
        onTap: onOpen,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onOpen();
          },
          haptic: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 44,
              maxWidth: MediaQuery.sizeOf(context).width * 0.92,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: kSunken,
                borderRadius: BorderRadius.circular(kRadiusField),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      saved ? Icons.bookmark_added_rounded : Icons.bookmark_remove_rounded,
                      size: 20,
                      color: kInkSecondary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: AppText.caption.copyWith(
                          color: kInkSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
