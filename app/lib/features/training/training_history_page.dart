import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/today.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/units_scope.dart';
import 'training_copy.dart';

/// The weeks of a month, Monday first, as dates; days outside the month are null.
List<List<DateTime?>> monthWeeks(int year, int month) {
  final first = DateTime.utc(year, month, 1);
  final days = DateUtils.getDaysInMonth(year, month);
  final cells = <DateTime?>[
    for (var i = 1; i < first.weekday; i++) null,
    for (var d = 1; d <= days; d++) DateTime.utc(year, month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
}

String monthKey(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';

/// The colour of the yoga and mobility dot: never the person's own accent, so the two dots differ.
Color yogaDotColor(BuildContext context) {
  final accent = context.accent;
  for (final id in const ['teal', 'sky']) {
    final fill = accentById(id).fill;
    if (fill != accent) return fill;
  }
  return kFlame;
}

/// Whether the plan had a session on [date]. The server only says whether one was completed, so
/// a day outside the plan's dates or weekdays counts as having none planned.
bool sessionPlanned(TrainingPlan? plan, DateTime date) {
  if (plan == null) return false;
  final key = formatDateKey(date);
  if (key.compareTo(plan.startsOn) < 0 || key.compareTo(plan.endsOn) > 0) return false;
  return plan.days.any((d) => d.weekday == date.weekday);
}

/// The words for one calendar day, read by VoiceOver and shown in the day sheet's summary.
String dayLabel(DateTime date, HistoryDay? day, {required bool isToday, bool planned = true}) {
  final count = day == null || !day.hasSets ? '' : (day.sets == 1 ? '1 set' : '${day.sets} sets');
  final sets = day == null || !day.hasSets
      ? null
      : day.sessionCompleted
      ? '$count, session completed'
      : planned
      ? '$count, session not completed'
      : '$count logged';
  final parts = <String>[
    if (isToday) 'today',
    ?sets,
    if (day != null && !day.hasSets && day.sessionCompleted) 'session completed',
    if (day != null && day.hasYoga) '${day.yogaMinutes} minutes of yoga or mobility',
    if (day != null && day.workoutTypes.isNotEmpty)
      'workouts: ${day.workoutTypes.map(workoutTypeLabel).join(', ')}',
  ];
  final head = dayLong(formatDateKey(date));
  return parts.isEmpty ? '$head, nothing logged' : '$head, ${parts.join(', ')}';
}

String workoutTypeLabel(String type) => switch (type) {
  'hiit' => 'HIIT',
  _ => type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}',
};

/// A month of training: a dot per day for the session and for yoga or mobility, and a sheet of
/// what was done when a day is tapped.
class TrainingHistoryPage extends ConsumerStatefulWidget {
  const TrainingHistoryPage({super.key});

  @override
  ConsumerState<TrainingHistoryPage> createState() => _TrainingHistoryPageState();
}

class _TrainingHistoryPageState extends ConsumerState<TrainingHistoryPage> {
  ({int year, int month})? _shown;

  ({int year, int month}) _current(String today) {
    final d = parseLocalDate(today);
    return (year: d.year, month: d.month);
  }

  void _step(int by, ({int year, int month}) now) {
    final shown = _shown ?? now;
    final next = DateTime.utc(shown.year, shown.month + by);
    HapticFeedback.selectionClick();
    setState(() => _shown = (year: next.year, month: next.month));
  }

  @override
  Widget build(BuildContext context) {
    final today =
        ref.watch(todayProvider.select((v) => v.value?.data.localToday)) ??
        formatDateKey(DateTime.now());
    final now = _current(today);
    final shown = _shown ?? now;
    final key = monthKey(shown.year, shown.month);
    final history = ref.watch(trainingHistoryProvider(key));
    final plan = ref.watch(trainingTodayProvider.select((v) => v.value?.data.plan));
    final atNow = shown == now;
    return PageScaffold(
      title: 'History',
      subtitle: 'Sessions, sets and yoga by day',
      children: [
        _MonthHeader(
          title: monthYear(shown.year, shown.month),
          onPrevious: () => _step(-1, now),
          onNext: atNow ? null : () => _step(1, now),
        ),
        const SizedBox(height: 8),
        AppCard(
          child: _MonthGrid(
            year: shown.year,
            month: shown.month,
            today: today,
            plan: plan,
            history: history.value,
            onDay: (date, day) => _openDay(context, date, day, plan),
          ),
        ),
        const SizedBox(height: 12),
        const _Legend(),
        if (history.error case final error?) ...[
          const SizedBox(height: 12),
          ErrorBlock(
            title: 'Could not load this month',
            error: error,
            onRetry: () async => ref.invalidate(trainingHistoryProvider(key)),
          ),
        ],
      ],
    );
  }

  Future<void> _openDay(BuildContext context, DateTime date, HistoryDay? day, TrainingPlan? plan) {
    HapticFeedback.selectionClick();
    return showAppSheet<void>(
      context,
      builder: (_) => _DaySheet(date: date, day: day, planned: sessionPlanned(plan, date)),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.title, required this.onPrevious, required this.onNext});

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _StepButton(label: 'Previous month', icon: Icons.chevron_left_rounded, onTap: onPrevious),
      Expanded(
        child: Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: AppText.headline),
        ),
      ),
      _StepButton(label: 'Next month', icon: Icons.chevron_right_rounded, onTap: onNext),
    ],
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      haptic: false,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 30, color: onTap == null ? kBorder : kInkSecondary),
      ),
    ),
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.today,
    required this.plan,
    required this.history,
    required this.onDay,
  });

  final int year;
  final int month;
  final String today;
  final TrainingPlan? plan;
  final TrainingHistoryMonth? history;
  final void Function(DateTime date, HistoryDay? day) onDay;

  @override
  Widget build(BuildContext context) {
    final weeks = monthWeeks(year, month);
    return Column(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(label, style: AppText.caption.copyWith(color: kInkMuted)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (final week in weeks)
          Row(
            children: [
              for (final date in week)
                Expanded(
                  child: date == null
                      ? const SizedBox(height: _kCellHeight)
                      : _DayCell(
                          date: date,
                          planned: sessionPlanned(plan, date),
                          day: history?.day(formatDateKey(date)),
                          isToday: formatDateKey(date) == today,
                          onTap: (day) => onDay(date, day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

const _kCellHeight = 56.0;

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.planned,
    required this.day,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final bool planned;
  final HistoryDay? day;
  final bool isToday;
  final void Function(HistoryDay? day) onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final d = day;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: dayLabel(date, d, isToday: isToday, planned: planned),
      onTap: () => onTap(d),
      child: Pressable(
        scale: 0.94,
        onTap: () => onTap(d),
        child: SizedBox(
          height: _kCellHeight,
          child: Center(
            child: Container(
              width: 44,
              height: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isToday ? context.accentTint : null,
                border: isToday ? Border.all(color: accent, width: kBorderWidth) : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: AppText.label.copyWith(
                      color: kInk,
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 9,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (d != null && (d.sessionCompleted || d.hasSets))
                          _Dot(color: accent, filled: d.sessionCompleted),
                        if (d != null && d.hasYoga) ...[
                          if (d.sessionCompleted || d.hasSets) const SizedBox(width: 3),
                          _Dot(color: yogaDotColor(context), filled: true),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? color : null,
      border: filled ? null : Border.all(color: color, width: 2),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = AppText.caption.copyWith(color: kInkSecondary);
    Widget entry(Widget dot, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: style)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 6,
      children: [
        entry(_Dot(color: context.accent, filled: true), 'Session completed'),
        entry(_Dot(color: context.accent, filled: false), 'Sets only'),
        entry(_Dot(color: yogaDotColor(context), filled: true), 'Yoga or mobility'),
      ],
    );
  }
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.date, required this.day, required this.planned});

  final DateTime date;
  final HistoryDay? day;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final d = day;
    final units = context.units;
    final byExercise = <String, List<HistorySet>>{};
    for (final set in d?.logged ?? const <HistorySet>[]) {
      byExercise.putIfAbsent(set.exercise, () => []).add(set);
    }
    final nothing = d == null || (!d.hasSets && !d.hasYoga && d.workoutTypes.isEmpty);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(dayLong(formatDateKey(date)), style: AppText.title),
            ),
            const SizedBox(height: 4),
            if (d != null && (d.hasSets || d.sessionCompleted))
              Text(
                d.sessionCompleted
                    ? 'Session completed'
                    : planned
                    ? 'Session not completed'
                    : 'Sets logged',
                style: AppText.label.copyWith(color: kInkSecondary),
              ),
            const SizedBox(height: 12),
            if (nothing)
              Text(
                'Nothing was logged this day.',
                style: AppText.body.copyWith(color: kInkSecondary),
              ),
            for (final entry in byExercise.entries) ...[
              Text(entry.value.first.name, style: AppText.label),
              const SizedBox(height: 2),
              for (final set in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    _setText(set, units),
                    style: AppText.body.copyWith(color: kInkSecondary),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (d != null && d.hasYoga) ...[
              const Text('Yoga and mobility', style: AppText.label),
              Text('${d.yogaMinutes} minutes', style: AppText.body.copyWith(color: kInkSecondary)),
              const SizedBox(height: 10),
            ],
            if (d != null && d.workoutTypes.isNotEmpty) ...[
              const Text('Workouts from Health', style: AppText.label),
              Text(
                d.workoutTypes.map(workoutTypeLabel).join(', '),
                style: AppText.body.copyWith(color: kInkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _setText(HistorySet set, Units units) {
  final timed = set.seconds != null;
  final base = amountLabel(timed ? set.seconds! : set.reps ?? 0, timed: timed);
  final load = set.loadKg;
  return load == null ? base : '$base at ${kgLabel(load, units)}';
}
