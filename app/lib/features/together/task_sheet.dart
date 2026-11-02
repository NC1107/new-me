import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../state/session.dart';
import '../../state/tasks.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../util/task_copy.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pill_chip.dart';
import '../../widgets/segmented.dart';

/// Round stakes to tap; any whole number up to [kTaskStakeMax] can be typed instead.
const kTaskStakeChips = [10, 25, 50, 100];

const kTaskIdeas = ['Call the vet', 'Book the dentist', 'Take out the bins'];

/// Adds a task, or edits [task], which is one of my own proposals that is still unanswered.
Future<void> showTaskSheet(BuildContext context, {GemTask? task}) =>
    showAppSheet<void>(context, builder: (_) => TaskSheet(task: task));

/// Title, who it is for, the stake in gems and the deadline. The other person agrees before the
/// task is live, so neither of you sets a stake on your own.
class TaskSheet extends ConsumerStatefulWidget {
  const TaskSheet({super.key, this.task});

  final GemTask? task;

  @override
  ConsumerState<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<TaskSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _stake = TextEditingController(
    text: widget.task == null ? '' : '${widget.task!.stake}',
  );
  int? _assigneeId;
  DateTime? _deadline;
  bool _busy = false;
  String? _error;

  GemTask? get _existing => widget.task;

  @override
  void initState() {
    super.initState();
    final t = _existing;
    if (t != null) {
      _assigneeId = t.assigneeId;
      final d = parseLocalDate(t.deadline);
      _deadline = DateTime(d.year, d.month, d.day);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _stake.dispose();
    super.dispose();
  }

  DateTime _today() {
    final now = ref.read(clockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  int? get _stakeValue {
    final v = int.tryParse(_stake.text.trim());
    return v == null || v < 1 || v > kTaskStakeMax ? null : v;
  }

  bool get _valid => _title.text.trim().isNotEmpty && _stakeValue != null && _deadline != null;

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _deadline = picked);
  }

  Future<void> _run(Future<void> Function(TasksNotifier tasks) action) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(tasksProvider.notifier));
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  Future<void> _submit(int me) {
    if (!_valid) return Future.value();
    final title = _title.text.trim();
    final stake = _stakeValue!;
    final assignee = _assigneeId ?? me;
    final deadline = isoDate(_deadline!);
    final existing = _existing;
    return _run(
      (tasks) => existing == null
          ? tasks.propose(title: title, assigneeId: assignee, stake: stake, deadline: deadline)
          : tasks.edit(
              existing.id,
              title: title == existing.title ? null : title,
              assigneeId: assignee == existing.assigneeId ? null : assignee,
              stake: stake == existing.stake ? null : stake,
              deadline: deadline == existing.deadline ? null : deadline,
            ),
    );
  }

  String _caption(String? partner) {
    final existing = _existing;
    if (existing == null) {
      return partner == null
          ? 'Finish it by the deadline to win the gems. Miss it and you lose them.'
          : '$partner agrees on it first. Finish by the deadline to win the gems; miss it and '
                'the assignee loses them.';
    }
    if (existing.declined) {
      return '${partner ?? 'Your partner'} declined it. Change it or withdraw it.';
    }
    return 'Waiting for ${partner ?? 'your partner'}. Changing it asks again.';
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider.select((s) => s.session?.userId)) ?? 0;
    final users =
        ref.watch(boardProvider.select((b) => b.value?.data.users)) ?? const <BoardUser>[];
    final partner = users.where((u) => u.id != me).firstOrNull;
    final person = context.accentPalette;
    final today = _today();
    final existing = _existing;
    final deadline = _deadline;
    final quick = <(String, DateTime)>[
      ('Today', today),
      ('Tomorrow', today.add(const Duration(days: 1))),
      ('In a week', today.add(const Duration(days: 7))),
    ];
    final onQuick = deadline != null && quick.any((q) => q.$2 == deadline);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(existing == null ? 'Add a task' : 'Edit task', style: AppText.title),
          ),
          const SizedBox(height: 4),
          Text(
            _caption(partner?.name),
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          const FieldLabel('What needs doing?'),
          AppTextField(
            controller: _title,
            hint: kTaskIdeas.first,
            semanticLabel: 'Task title',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(kTaskTitleMax)],
            onChanged: (_) => setState(() {}),
          ),
          if (existing == null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final idea in kTaskIdeas)
                  PillChip(
                    label: idea,
                    selected: _title.text.trim() == idea,
                    palette: person,
                    onTap: () => setState(() => _title.text = idea),
                  ),
              ],
            ),
          ],
          if (partner != null) ...[
            const SizedBox(height: 20),
            const FieldLabel('Who does it?'),
            Segmented<int>(
              options: [(me, 'Me'), (partner.id, partner.name)],
              selected: _assigneeId ?? me,
              onChanged: (id) => setState(() => _assigneeId = id),
              spokenLabel: (id) => id == me ? 'Me' : partner.name,
            ),
          ],
          const SizedBox(height: 20),
          const FieldLabel('Gems at stake'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in kTaskStakeChips)
                PillChip(
                  label: n.formatted,
                  selected: _stakeValue == n,
                  palette: person,
                  onTap: () => setState(() => _stake.text = '$n'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _stake,
            hint: 'Or type a number',
            semanticLabel: 'Gems at stake',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            errorText: _stake.text.isNotEmpty && _stakeValue == null
                ? 'Between 1 and ${kTaskStakeMax.formatted}'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Text(
            'Won when it is done in time, lost when the deadline passes.',
            style: AppText.caption,
          ),
          const SizedBox(height: 20),
          const FieldLabel('Due by the end of'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, date) in quick)
                PillChip(
                  label: label,
                  selected: deadline == date,
                  palette: person,
                  onTap: () => setState(() => _deadline = date),
                ),
              PillChip(
                label: deadline != null && !onQuick
                    ? dayWithWeekday(isoDate(deadline))
                    : 'Pick a date',
                selected: deadline != null && !onQuick,
                palette: person,
                onTap: _pickDate,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 20),
          Semantics(
            container: true,
            child: ChunkyButton(
              label: existing == null
                  ? (partner == null ? 'Add task' : 'Propose task')
                  : (existing.declined ? 'Propose again' : 'Save'),
              busy: _busy,
              onPressed: _valid && !_busy ? () => _submit(me) : null,
            ),
          ),
          if (existing != null) ...[
            const SizedBox(height: 10),
            ChunkyButton.secondary(
              label: 'Withdraw',
              onPressed: _busy ? null : () => _run((t) => t.withdraw(existing.id)),
            ),
          ],
        ],
      ),
    );
  }
}
