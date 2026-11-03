import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/habit_proposals.dart';
import '../../state/session.dart';
import '../../state/tasks.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../util/task_copy.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable.dart';
import 'task_sheet.dart';

/// The Tasks part of Us: agreed tasks of both people with a Done button on mine, my proposals
/// that wait for an answer, a row to add one, and the last few that were finished or missed.
class TasksSection extends ConsumerStatefulWidget {
  const TasksSection({super.key});

  @override
  ConsumerState<TasksSection> createState() => _TasksSectionState();
}

class _TasksSectionState extends ConsumerState<TasksSection> {
  int? _finishing;
  String? _error;

  Future<void> _finish(GemTask task) async {
    if (_finishing != null) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _finishing = task.id;
      _error = null;
    });
    try {
      await ref.read(tasksProvider.notifier).finish(task.id);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    }
    if (mounted) setState(() => _finishing = null);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final list = ref.watch(tasksProvider).value;
    if (list == null) return const SizedBox.shrink();
    final partner = ref.watch(partnerNameProvider);
    final live = list.live;
    final waiting = list.mineOpen(userId);
    if (live.isEmpty && waiting.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmptyTasks(onAdd: () => showTaskSheet(context)),
          if (list.history.isNotEmpty) _History(list: list, userId: userId),
        ],
      );
    }
    final rows = <Widget>[
      for (final t in live)
        _TaskRow(
          key: ValueKey(t.id),
          task: t,
          userId: userId,
          busy: _finishing == t.id,
          locked: _finishing != null,
          onDone: () => _finish(t),
        ),
      for (final t in waiting)
        _WaitingRow(
          key: ValueKey(t.id),
          task: t,
          partner: partner,
          onTap: () => showTaskSheet(context, task: t),
        ),
      _AddTaskRow(onTap: () => showTaskSheet(context)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, row) in rows.indexed) ...[if (i > 0) const _Rule(), row],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        if (list.history.isNotEmpty) _History(list: list, userId: userId),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.list, required this.userId});

  final TaskList list;
  final int? userId;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 28),
      Semantics(header: true, child: const Text('Tasks settled', style: AppText.headline)),
      const SizedBox(height: 10),
      _TaskHistory(items: list.history.take(5).toList(), userId: userId),
    ],
  );
}

/// Nothing agreed yet: say what a task is for, with the one way in.
class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Mascot(size: 72)),
        const SizedBox(height: 12),
        Text(
          'No tasks yet',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        const Text(
          'One-off jobs like calling the vet or booking the dentist.',
          textAlign: TextAlign.center,
          style: AppText.caption,
        ),
        const SizedBox(height: 16),
        ChunkyButton.secondary(label: 'Add a task', onPressed: onAdd),
      ],
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => const Divider(height: 2, thickness: 2, color: kBorder);
}

String _who(GemTask t, int? userId) => t.assignedTo(userId) ? 'You' : t.assigneeName;

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.userId,
    required this.busy,
    required this.locked,
    required this.onDone,
  });

  final GemTask task;
  final int? userId;
  final bool busy;
  final bool locked;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final mine = task.assignedTo(userId);
    final detail =
        '${_who(task, userId)} · ${task.stake.formatted} gems · '
        '${dueLabel(task.daysLeft, task.deadline)}'
        '${task.loseIfMissed ? ' · lost if missed' : ''}';
    final canFinish = mine && !task.overdue;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: MergeSemantics(
                child: Row(
                  children: [
                    Icon(
                      mine ? Icons.radio_button_unchecked_rounded : Icons.person_outline_rounded,
                      size: 22,
                      color: mine ? context.accentLip : kInkSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.tabular(
                              AppText.caption.copyWith(
                                color: task.overdue ? kDangerText : kInkSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (canFinish) ...[
              const SizedBox(width: 12),
              Semantics(
                container: true,
                label: 'Mark ${task.title} done',
                child: SizedBox(
                  width: 96,
                  child: ChunkyButton(label: 'Done', busy: busy, onPressed: locked ? null : onDone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({super.key, required this.task, required this.partner, required this.onTap});

  final GemTask task;
  final String? partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final terms =
        '${task.stake.formatted} gems · ${dueLabel(task.daysLeft, task.deadline)}'
        '${task.loseIfMissed ? ' · lost if missed' : ''}';
    final (icon, color, detail) = task.declined
        ? (Icons.block_rounded, kDangerText, '$terms · declined')
        : (
            Icons.hourglass_top_rounded,
            kInkSecondary,
            '$terms · waiting for ${partner ?? 'an answer'}',
          );
    return Semantics(
      button: true,
      label: '${task.title}, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
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
    );
  }
}

class _AddTaskRow extends StatelessWidget {
  const _AddTaskRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a task',
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      scale: 0.99,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, size: 22, color: kInk),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Add a task', style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TaskHistory extends StatelessWidget {
  const _TaskHistory({required this.items, required this.userId});

  final List<GemTask> items;
  final int? userId;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      children: [
        for (final (i, t) in items.indexed) ...[
          if (i > 0) const _Rule(),
          Builder(
            builder: (context) {
              final gems = t.done ? ' · +${t.stake.formatted} gems' : '';
              final cost = t.missed && t.lost > 0 ? ' · -${t.lost.formatted} gems' : '';
              final detail = '${_who(t, userId)} ${t.done ? 'finished' : 'missed'}$gems$cost';
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Semantics(
                  container: true,
                  label: '${t.title}, $detail',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          t.done ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 22,
                          color: t.done ? kSuccess : kDangerText,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(detail, style: AppText.tabular(AppText.caption)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}
