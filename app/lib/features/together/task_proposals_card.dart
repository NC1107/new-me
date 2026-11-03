import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/tasks.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../util/task_copy.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/pressable.dart';
import 'task_sheet.dart';

/// Tasks my partner proposed, one row each with Agree, Change the amount and Not now, for the
/// Action needed card.
class TaskProposalRows extends ConsumerWidget {
  const TaskProposalRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final proposals = ref.watch(tasksProvider).value?.proposalsFor(userId) ?? const <GemTask>[];
    if (proposals.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, t) in proposals.indexed) ...[
          if (i > 0) const Divider(height: 24, thickness: 2, color: kBorder),
          _ProposalRow(key: ValueKey(t.id), task: t, userId: userId),
        ],
      ],
    );
  }
}

class _ProposalRow extends ConsumerStatefulWidget {
  const _ProposalRow({super.key, required this.task, required this.userId});

  final GemTask task;
  final int? userId;

  @override
  ConsumerState<_ProposalRow> createState() => _ProposalRowState();
}

class _ProposalRowState extends ConsumerState<_ProposalRow> {
  bool? _agreeing;
  String? _error;

  Future<void> _answer(bool agree) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _agreeing = agree;
      _error = null;
    });
    try {
      await ref.read(tasksProvider.notifier).answer(widget.task.id, agree: agree);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _agreeing = null;
          _error = errorCopy(e);
        });
      }
    }
  }

  String get _summary {
    final t = widget.task;
    final from = t.creatorName.isEmpty ? 'Your partner' : t.creatorName;
    final terms = '${t.stake.formatted} gems, ${dueLabel(t.daysLeft, t.deadline)}';
    final atStake = t.loseIfMissed ? ', and loses them if missed' : '';
    return t.assignedTo(widget.userId)
        ? '$from asks you to ${t.title}: $terms'
        : '$from takes on ${t.title}: $terms$atStake';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _agreeing != null;
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
              child: Icon(Icons.task_alt_rounded, size: 22, color: context.accentLip),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_summary, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChunkyButton.secondary(
                label: 'Not now',
                busy: _agreeing == false,
                onPressed: busy ? null : () => _answer(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                label: 'Agree',
                busy: _agreeing == true,
                onPressed: busy ? null : () => _answer(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Semantics(
          button: true,
          label: 'Change the amount of ${widget.task.title}',
          excludeSemantics: true,
          onTap: busy ? null : () => showCounterSheet(context, task: widget.task),
          child: Pressable(
            onTap: busy ? null : () => showCounterSheet(context, task: widget.task),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text(
                  'Change the amount',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800, color: kInk),
                ),
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: AppText.label.copyWith(color: kDangerText)),
        ],
      ],
    );
  }
}
