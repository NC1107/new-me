import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/habit_models.dart';
import '../../reminders/habit_reminder_plan.dart';
import '../../reminders/reminder_plan.dart';
import '../../state/habit_reminders.dart';
import '../../state/habit_proposals.dart';
import '../../state/habits.dart';
import '../../state/local_prefs.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/segmented.dart';
import 'habit_icons.dart';
import 'habit_templates.dart';
import 'slot_time_sheet.dart';

class _SlotForm {
  _SlotForm({String label = '', this.minutes, this.reminder = true})
    : label = TextEditingController(text: label);

  final TextEditingController label;
  int? minutes;
  bool reminder;
}

const _kDayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _kDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Creates a habit, or edits [habit]. A new one starts from a template so the usual habits are
/// a pick and a save.
class HabitEditorPage extends ConsumerStatefulWidget {
  const HabitEditorPage({super.key, this.habit});

  final Habit? habit;

  @override
  ConsumerState<HabitEditorPage> createState() => _HabitEditorPageState();
}

class _HabitEditorPageState extends ConsumerState<HabitEditorPage> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  String _icon = kDefaultHabitIcon;
  Set<int> _days = {...kEveryDay};
  String _kind = HabitKind.check;
  final List<_SlotForm> _slots = [_SlotForm(label: 'Daily')];
  int _target = 8;
  int? _minutes;
  // A habit made before minutes keeps its gems until its minutes are chosen.
  bool _minutesChosen = true;
  HabitTemplate? _template;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    if (habit != null) _load(habit);
  }

  Future<void> _load(Habit habit) async {
    final muted = await LocalPrefs.mutedHabitSlots();
    if (!mounted) return;
    setState(() {
      _name.text = habit.name;
      _icon = kHabitIcons.containsKey(habit.icon) ? habit.icon : kDefaultHabitIcon;
      _days = {...habit.weekdays};
      _kind = habit.kind;
      _target = habit.target ?? 8;
      _minutes = habit.pending ? habit.proposedMinutes : habit.minutes;
      _minutesChosen = habit.pending || habit.minutes != null || habit.points == 0;
      _slots
        ..clear()
        ..addAll([
          for (final (i, s) in habit.slots.indexed)
            _SlotForm(
              label: s.label,
              minutes: s.minutes,
              reminder: !muted.contains(slotKey(habit.id, i)),
            ),
        ]);
      if (_slots.isEmpty) _slots.add(_SlotForm(label: 'Daily'));
    });
  }

  /// A removed slot's field is still in the tree for one more frame, so it is disposed with the
  /// page rather than at once.
  final _retired = <_SlotForm>[];

  void _retire(_SlotForm slot) => _retired.add(slot);

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    for (final s in [..._slots, ..._retired]) {
      s.label.dispose();
    }
    super.dispose();
  }

  void _applyTemplate(HabitTemplate t) {
    HapticFeedback.selectionClick();
    setState(() {
      _template = t;
      _error = null;
      _name.text = t.name;
      _icon = t.icon;
      _days = {...t.weekdays};
      _kind = t.isCount ? HabitKind.count : HabitKind.check;
      _target = t.target ?? 8;
      _slots.forEach(_retire);
      _slots
        ..clear()
        ..addAll([for (final s in t.slots) _SlotForm(label: s.label, minutes: s.minutes)]);
      if (_slots.isEmpty) _slots.add(_SlotForm(label: 'Daily'));
    });
    if (t.custom) _nameFocus.requestFocus();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Give the habit a name.';
    if (_days.isEmpty) return 'Pick at least one day.';
    if (_kind == HabitKind.check) {
      if (_slots.any((s) => s.label.text.trim().isEmpty)) return 'Give each time a name.';
    }
    return null;
  }

  HabitDraft _draft() => HabitDraft(
    name: _name.text.trim(),
    icon: _icon,
    kind: _kind,
    weekdays: (_days.toList()..sort()),
    slots: _kind == HabitKind.check
        ? [
            for (final s in _slots)
              HabitSlot(
                label: s.label.text.trim(),
                time: s.minutes == null ? null : slotTimeString(s.minutes!),
              ),
          ]
        : const [],
    target: _kind == HabitKind.count ? _target : null,
    minutes: _minutes,
  );

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      HapticFeedback.mediumImpact();
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = _draft();
    final notifier = ref.read(habitsProvider.notifier);
    try {
      final int id;
      if (_editing) {
        id = widget.habit!.id;
        await notifier.save(id, draft);
      } else {
        id = (await notifier.create(draft)).id;
      }
      await _saveReminders(id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// The per-slot reminder choice is local, so it is stored here and the system is asked for
  /// permission only when a timed slot actually wants one.
  Future<void> _saveReminders(int id) async {
    final muted = await LocalPrefs.mutedHabitSlots();
    muted.removeWhere((k) => k.startsWith('$id:'));
    var wantsReminder = false;
    if (_kind == HabitKind.check) {
      for (final (i, s) in _slots.indexed) {
        if (s.minutes == null) continue;
        if (s.reminder) {
          wantsReminder = true;
        } else {
          muted.add(slotKey(id, i));
        }
      }
    }
    await LocalPrefs.setMutedHabitSlots(muted);
    final reminders = ref.read(habitRemindersProvider.notifier);
    if (wantsReminder) {
      unawaited(reminders.ensurePermission());
    } else {
      reminders.reschedule();
    }
  }

  Future<void> _pickTime(_SlotForm slot) async {
    final choice = await showSlotTimeSheet(context, current: slot.minutes);
    if (choice == null || !mounted) return;
    setState(() => slot.minutes = choice.minutes);
  }

  void _setDays(Iterable<int> days) {
    HapticFeedback.selectionClick();
    setState(() => _days = {...days});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    final isCount = _kind == HabitKind.count;
    return PageScaffold(
      title: _editing ? 'Edit habit' : 'New habit',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: kDanger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppText.label.copyWith(
                        color: kDangerText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ChunkyButton(label: 'Save', busy: _busy, palette: palette, onPressed: _save),
        ],
      ),
      children: [
        if (!_editing) ...[
          const FieldLabel('Start from'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in kHabitTemplates)
                _Pill(
                  label: t.custom ? 'Custom' : t.name,
                  selected: identical(_template, t),
                  onTap: () => _applyTemplate(t),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        const FieldLabel('Name'),
        AppTextField(
          controller: _name,
          hint: 'Brush teeth',
          semanticLabel: 'Habit name',
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Icon'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in kHabitIcons.keys)
              _IconChoice(
                iconKey: key,
                selected: key == _icon,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _icon = key);
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Days'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              label: 'Every day',
              selected: _days.length == 7,
              onTap: () => _setDays(kEveryDay),
            ),
            _Pill(
              label: 'Weekdays',
              selected: _days.length == 5 && kWeekdays.every(_days.contains),
              onTap: () => _setDays(kWeekdays),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var d = 1; d <= 7; d++)
              _DayChip(
                letter: _kDayLetters[d - 1],
                name: _kDayNames[d - 1],
                on: _days.contains(d),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _days = _days.contains(d) ? ({..._days}..remove(d)) : {..._days, d};
                    _error = null;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Minutes it takes'),
        // A habit from before minutes has none chosen, so -1 selects no segment until one is.
        Segmented<int>(
          options: [for (final m in kHabitMinuteChoices) (m ?? 0, m == null ? 'Track' : '$m')],
          selected: _minutesChosen ? (_minutes ?? 0) : -1,
          spokenLabel: (m) => m == 0 ? 'Only track' : '$m minutes',
          onChanged: (m) {
            setState(() {
              _minutes = m == 0 ? null : m;
              _minutesChosen = true;
            });
          },
        ),
        const SizedBox(height: 8),
        _GemsNote(
          habit: widget.habit,
          minutes: _minutes,
          chosen: _minutesChosen,
          partner: ref.watch(partnerNameProvider),
        ),
        if (!_editing) ...[
          const SizedBox(height: 20),
          const FieldLabel('Marked'),
          Segmented<String>(
            options: const [(HabitKind.check, 'Times of day'), (HabitKind.count, 'Count')],
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
        ],
        const SizedBox(height: 20),
        if (isCount) ...[
          const FieldLabel('Daily target'),
          _TargetStepper(
            value: _target,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _target = v);
            },
          ),
        ] else ...[
          const FieldLabel('Times'),
          for (final (i, slot) in _slots.indexed) ...[
            if (i > 0) const SizedBox(height: kCardGap),
            _SlotCard(
              slot: slot,
              removable: _slots.length > 1,
              onTime: () => _pickTime(slot),
              onReminder: (on) => setState(() => slot.reminder = on),
              onRemove: () => setState(() {
                _slots.remove(slot);
                _retire(slot);
              }),
              onChanged: () => setState(() => _error = null),
            ),
          ],
          if (_slots.length < kMaxHabitSlots) ...[
            const SizedBox(height: kCardGap),
            ChunkyButton.secondary(
              label: 'Add a time',
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _slots.add(_SlotForm())),
            ),
          ],
        ],
      ],
    );
  }
}

/// The gems the chosen minutes are worth, and where the partner's approval stands.
class _GemsNote extends StatelessWidget {
  const _GemsNote({
    required this.habit,
    required this.minutes,
    required this.chosen,
    required this.partner,
  });

  final Habit? habit;
  final int? minutes;
  final bool chosen;
  final String? partner;

  @override
  Widget build(BuildContext context) {
    final habit = this.habit;
    final gems = chosen ? habitGems(minutes) : habit?.points ?? 0;
    final changed = chosen && (habit == null ? minutes != null : minutes != habit.minutes);
    final String text;
    if (habit != null && habit.pending && minutes == habit.proposedMinutes) {
      text = 'Waiting for ${partner ?? 'your partner'} to approve ${habit.proposedPoints} gems';
    } else if (changed && partner != null) {
      text = '$gems gems, once $partner approves';
    } else {
      text = '$gems gems';
    }
    return Semantics(
      liveRegion: true,
      child: Text(text, style: AppText.label.copyWith(color: kInkSecondary)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          // No alignment: it would stretch the pill to the full row inside a Wrap.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? palette.tint : kSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? palette.fill : kBorder, width: kBorderWidth),
          ),
          child: Text(
            label,
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? palette.lip : kInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.iconKey, required this.selected, required this.onTap});

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      button: true,
      selected: selected,
      label: habitIconLabel(iconKey),
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? palette.fill : palette.tint,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: palette.lip, width: kBorderWidth) : null,
          ),
          child: Icon(habitIcon(iconKey), size: 22, color: selected ? palette.onFill : palette.lip),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.letter, required this.name, required this.on, required this.onTap});

  final String letter;
  final String name;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      button: true,
      selected: on,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? palette.fill : kSurface,
            shape: BoxShape.circle,
            border: Border.all(color: on ? palette.lip : kBorder, width: kBorderWidth),
          ),
          child: Text(
            letter,
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w900,
              color: on ? palette.onFill : kInkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.removable,
    required this.onTime,
    required this.onReminder,
    required this.onRemove,
    required this.onChanged,
  });

  final _SlotForm slot;
  final bool removable;
  final VoidCallback onTime;
  final ValueChanged<bool> onReminder;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    final minutes = slot.minutes;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: slot.label,
                  hint: 'Morning',
                  semanticLabel: 'Time name',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (removable) ...[
                const SizedBox(width: 8),
                ChunkyIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Remove time',
                  size: 44,
                  kind: ChunkyKind.secondary,
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: minutes == null ? 'Set a time' : 'Time ${formatReminderTime(minutes)}',
            excludeSemantics: true,
            onTap: onTime,
            child: Pressable(
              onTap: onTime,
              scale: 0.98,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: kSunken,
                  borderRadius: BorderRadius.circular(kRadiusField),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 20, color: palette.lip),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        minutes == null ? 'Any time' : formatReminderTime(minutes),
                        style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: kInkMuted),
                  ],
                ),
              ),
            ),
          ),
          if (minutes != null)
            MergeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    const Expanded(child: Text('Remind me', style: AppText.body)),
                    Switch(value: slot.reminder, onChanged: onReminder),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TargetStepper extends StatelessWidget {
  const _TargetStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChunkyIconButton(
          icon: Icons.remove_rounded,
          semanticLabel: 'Lower target',
          size: 52,
          kind: ChunkyKind.secondary,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Column(
            children: [
              Text('$value', style: AppText.tabular(AppText.display)),
              const Text('times a day', style: AppText.caption),
            ],
          ),
        ),
        ChunkyIconButton(
          icon: Icons.add_rounded,
          semanticLabel: 'Raise target',
          size: 52,
          onPressed: value < kMaxHabitTarget ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
