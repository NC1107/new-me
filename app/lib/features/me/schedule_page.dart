import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../reminders/reminder_plan.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import 'timezone_page.dart';

const _kWeekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "10 min after you wake", or "as soon as you wake" at zero.
String offsetLabel(int minutes) {
  if (minutes == 0) return 'As soon as you wake';
  final h = minutes ~/ 60, m = minutes % 60;
  final gap = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
  return '$gap after you wake';
}

/// The wait after waking for a chosen start time, within 0 to [kMaxFirstOffsetMin]; a start
/// before waking means as soon as you wake.
int dayStartOffset(int wake, int start) {
  final gap = (start - wake) % (24 * 60);
  return gap > kMaxFirstOffsetMin ? 0 : gap;
}

/// "07:10" or "7:10 AM": when the first notification arrives for a wake time and offset.
String firstNotificationAt(DayTimes times, int offsetMin) =>
    formatReminderTime((times.wake + offsetMin) % (24 * 60));

/// "Weekdays" for Monday to Friday, "Every day", "Weekends", or the day names.
String workdaysLabel(List<int> days) {
  final set = days.toSet();
  if (set.isEmpty) return 'No workdays';
  if (set.length == 7) return 'Every day';
  if (set.length == 5 && set.containsAll([1, 2, 3, 4, 5])) return 'Mon to Fri';
  if (set.length == 2 && set.containsAll([6, 7])) return 'Weekends';
  return [for (final d in set.toList()..sort()) _kWeekdayNames[d - 1].substring(0, 3)].join(', ');
}

/// Me > Schedule: which days are workdays, wake and bed time for workdays and days off, and how
/// soon after waking the first notification may come. Everything time-based follows it.
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  Schedule? _edited;
  String? _zone;
  bool _busy = false;
  String? _error;

  Schedule get _saved => ref.read(meProvider).value?.data.schedule ?? const Schedule();

  /// What the page shows: the person's edit, else what the server has (which may load after the
  /// page opens).
  Schedule get _draft => _edited ?? _saved;

  String get _savedZone => ref.read(meProvider).value?.data.user.timezone ?? '';

  bool get _dirty =>
      (_edited != null && _edited != _saved) || (_zone != null && _zone != _savedZone);

  void _edit(Schedule next) => setState(() {
    _edited = next;
    _error = null;
  });

  String? _invalid() {
    if (_draft.workday.wake == _draft.workday.bed) return 'On workdays, wake and bed must differ.';
    if (_draft.dayOff.wake == _draft.dayOff.bed) return 'On days off, wake and bed must differ.';
    return null;
  }

  Future<void> _save() async {
    final problem = _invalid();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(meProvider.notifier)
          .save(
            MePatch(
              schedule: _edited != null && _edited != _saved ? _draft : null,
              timezone: _zone != null && _zone != _savedZone ? _zone : null,
            ),
          );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).maybePop();
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException && e.code == 'invalid_timezone'
              ? 'The server does not know "$_zone".'
              : errorCopy(e),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toggleDay(int day) {
    final days = _draft.workdays.toSet();
    if (!days.add(day)) days.remove(day);
    _edit(_draft.copyWith(workdays: days.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    // Subscribes the page, so a profile that loads late replaces the defaults shown at first.
    ref.watch(meProvider);
    final offset = _draft.firstNotificationOffsetMin;
    return PageScaffold(
      title: 'Schedule',
      footer: ChunkyButton(label: 'Save', busy: _busy, onPressed: _dirty && !_busy ? _save : null),
      children: [
        Text(
          'Reminders, nudges and quiet hours follow this. Nothing is sent between your bedtime '
          'and your first notification of the day.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Semantics(header: true, child: const Text('Workdays', style: AppText.headline)),
        const SizedBox(height: 10),
        _WeekdayChips(days: _draft.workdays, onToggle: _toggleDay),
        const SizedBox(height: 6),
        Text(workdaysLabel(_draft.workdays), style: AppText.caption),
        const SizedBox(height: 20),
        _DayTimesCard(
          title: 'On workdays',
          times: _draft.workday,
          onChanged: (t) => _edit(_draft.copyWith(workday: t)),
        ),
        const SizedBox(height: kCardGap),
        _DayTimesCard(
          title: 'On days off',
          times: _draft.dayOff,
          onChanged: (t) => _edit(_draft.copyWith(dayOff: t)),
        ),
        const SizedBox(height: 24),
        Semantics(header: true, child: const Text('Your day starts', style: AppText.headline)),
        const SizedBox(height: 4),
        Text(
          'Your first note waits until then, even if you are up earlier.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TimeField(
          label: 'On workdays at',
          minutes: (_draft.workday.wake + offset) % (24 * 60),
          onChanged: (start) => _edit(
            _draft.copyWith(firstNotificationOffsetMin: dayStartOffset(_draft.workday.wake, start)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${offsetLabel(offset)}. On days off: ${firstNotificationAt(_draft.dayOff, offset)}.',
          style: AppText.caption,
        ),
        const SizedBox(height: 24),
        Semantics(header: true, child: const Text('Time zone', style: AppText.headline)),
        const SizedBox(height: 4),
        Text(
          'Your day runs on this clock. A new zone applies from the next day.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TimezonePicker(
          selected: _zone ?? _savedZone,
          onChanged: (zone) => setState(() {
            _zone = zone;
            _error = null;
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: kDangerText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.days, required this.onToggle});

  final List<int> days;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Builder(
              builder: (context) {
                final day = i + 1;
                final on = days.contains(day);
                return Semantics(
                  button: true,
                  toggled: on,
                  label: _kWeekdayNames[i],
                  excludeSemantics: true,
                  onTap: () => onToggle(day),
                  child: Pressable(
                    scale: 0.96,
                    onTap: () => onToggle(day),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? palette.tint : kSurface,
                        borderRadius: BorderRadius.circular(kRadiusField),
                        border: Border.all(color: on ? palette.fill : kBorder, width: kBorderWidth),
                      ),
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Text(
                          _kWeekdayLetters[i],
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w900,
                            color: on ? palette.lip : kInkSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _DayTimesCard extends StatelessWidget {
  const _DayTimesCard({required this.title, required this.times, required this.onChanged});

  final String title;
  final DayTimes times;
  final ValueChanged<DayTimes> onChanged;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TimeField(
                label: 'Wake up',
                minutes: times.wake,
                onChanged: (m) => onChanged(times.copyWith(wake: m)),
              ),
            ),
            const SizedBox(width: kCardGap),
            Expanded(
              child: TimeField(
                label: 'Bedtime',
                minutes: times.bed,
                onChanged: (m) => onChanged(times.copyWith(bed: m)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A labelled time that opens the time picker; [minutes] are after midnight.
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.minutes, required this.onChanged});

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: label,
    );
    if (picked != null) onChanged(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final text = formatReminderTime(minutes);
    return Semantics(
      button: true,
      label: '$label, $text',
      excludeSemantics: true,
      onTap: () => _pick(context),
      child: Pressable(
        onTap: () => _pick(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kSunken,
            borderRadius: BorderRadius.circular(kRadiusField),
            border: Border.all(color: kBorder, width: kBorderWidth),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.caption),
              Text(
                text,
                style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
