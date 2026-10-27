import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/habit_models.dart';
import '../../api/models.dart';
import '../../state/habit_marks.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/skeletons.dart';
import 'count_sheet.dart';
import 'habit_chip.dart';
import 'habit_items.dart';

String _previousDate(String date) {
  final d = DateTime.parse(date);
  final prev = DateTime.utc(d.year, d.month, d.day - 1);
  return '${prev.year.toString().padLeft(4, '0')}-${prev.month.toString().padLeft(2, '0')}-'
      '${prev.day.toString().padLeft(2, '0')}';
}

/// Yesterday's habits, markable until the grace window closes like yesterday's log entries.
Future<void> showYesterdayHabits(BuildContext context, {required Today today}) =>
    showAppSheet<void>(
      context,
      builder: (_) => _DayHabitsSheet(date: _previousDate(today.localToday)),
    );

class _DayHabitsSheet extends ConsumerStatefulWidget {
  const _DayHabitsSheet({required this.date});

  final String date;

  @override
  ConsumerState<_DayHabitsSheet> createState() => _DayHabitsSheetState();
}

class _DayHabitsSheetState extends ConsumerState<_DayHabitsSheet> {
  List<HabitState>? _habits;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      final day = await client.today(date: widget.date);
      if (mounted) {
        setState(() {
          _habits = day.habits;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _mark(StripItem item, {int? count}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final marks = ref.read(habitMarksProvider);
    try {
      final result = await marks.markOtherDay(
        widget.date,
        item.habit.id,
        slot: item.slot?.index,
        done: item.isCount ? null : !item.done,
        count: item.isCount ? (count ?? item.habit.count + 1) : null,
      );
      if (mounted) setState(() => _habits = result.habits);
    } on ApiException catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorCopy(e))));
    }
  }

  Future<void> _setCount(StripItem item) async {
    final value = await showCountSheet(context, habit: item.habit);
    if (value != null && mounted) await _mark(item, count: value);
  }

  @override
  Widget build(BuildContext context) {
    final habits = _habits;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, kGutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: const Text('Yesterday', style: AppText.title)),
          const SizedBox(height: 12),
          if (habits == null && _error != null)
            ErrorBlock(
              title: 'Could not load yesterday',
              error: _error!,
              onRetry: () async {
                setState(() => _error = null);
                await _load();
              },
            )
          else if (habits == null)
            const SkeletonBlock(height: 52, radius: 26)
          else if (habits.isEmpty)
            Text('Nothing was due.', style: AppText.body.copyWith(color: kInkSecondary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in stripItems(habits, nowMinutes: -1))
                  ConstrainedBox(
                    key: ValueKey(item.key),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 2 * kGutter,
                    ),
                    child: HabitChip(
                      item: item,
                      onTap: () => _mark(item),
                      onLongPress: item.isCount ? () => _setCount(item) : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
