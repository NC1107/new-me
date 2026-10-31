import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/shared_habit_models.dart';
import '../../state/habit_proposals.dart';
import '../../state/shared_habits.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/dialogs.dart';
import '../habits/habit_editor_page.dart';
import '../habits/habit_icons.dart';
import 'shared_habit_templates.dart';

/// Adds a household habit, or edits [habit].
Future<void> showSharedHabitSheet(BuildContext context, {SharedHabit? habit}) =>
    showAppSheet<void>(context, builder: (_) => SharedHabitSheet(habit: habit));

const _kDefaultIcon = 'home';
const _kEveryNDefault = 3;

/// The household icons come first, since those are what a chore usually needs.
const _kChoreIcons = [
  'home',
  'local_laundry_service',
  'cleaning_services',
  'delete',
  'shopping_cart',
];
final _kIconOrder = [
  ..._kChoreIcons,
  for (final key in kHabitIcons.keys)
    if (!_kChoreIcons.contains(key)) key,
];

/// Name a chore, pick its icon and how often it comes round. For an existing one it also holds
/// the delete, which asks first because it goes away for both of you.
class SharedHabitSheet extends ConsumerStatefulWidget {
  const SharedHabitSheet({super.key, this.habit});

  final SharedHabit? habit;

  @override
  ConsumerState<SharedHabitSheet> createState() => _SharedHabitSheetState();
}

class _SharedHabitSheetState extends ConsumerState<SharedHabitSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.habit?.name ?? '');
  late String _icon = widget.habit?.icon ?? _kDefaultIcon;
  late String _kind = widget.habit?.schedule.kind ?? SharedKind.weekly;
  late Set<int> _days = {...?widget.habit?.schedule.weekdays};
  late int _every = widget.habit?.schedule.everyDays ?? _kEveryNDefault;
  bool _busy = false;
  String? _error;

  SharedHabit? get _existing => widget.habit;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SharedSchedule get _schedule => SharedSchedule(
    kind: _kind,
    weekdays: _days.toList()..sort(),
    everyDays: _kind == SharedKind.everyN ? _every : null,
  );

  bool get _valid => _name.text.trim().isNotEmpty && _schedule.valid;

  void _useTemplate(SharedHabitTemplate t) {
    HapticFeedback.selectionClick();
    setState(() {
      _name.text = t.name;
      _icon = t.icon;
      _kind = t.schedule.kind;
      _every = t.schedule.everyDays ?? _kEveryNDefault;
      _error = null;
    });
  }

  Future<void> _run(Future<void> Function(SharedHabitsNotifier) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(sharedHabitsProvider.notifier));
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

  Future<void> _submit() {
    if (!_valid) return Future.value();
    HapticFeedback.mediumImpact();
    final name = _name.text.trim();
    final existing = _existing;
    return _run(
      (n) => existing == null
          ? n.create(name, _icon, _schedule)
          : n.save(existing.id, name, _icon, _schedule),
    );
  }

  Future<void> _delete() async {
    final existing = _existing!;
    final partner = ref.read(partnerNameProvider);
    final ok = await confirmDialog(
      context,
      title: 'Delete ${existing.name}?',
      message: partner == null
          ? 'It goes off the list.'
          : 'It goes off the list for both of you. Gems already earned from it stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    await _run((n) => n.delete(existing.id));
  }

  void _toggleDay(int d) {
    HapticFeedback.selectionClick();
    setState(() {
      _days = _days.contains(d) ? ({..._days}..remove(d)) : {..._days, d};
      _error = null;
    });
  }

  void _setKind(String kind) {
    HapticFeedback.selectionClick();
    setState(() {
      _kind = kind;
      if (kind == SharedKind.weekdays && _days.isEmpty) _days = {1, 2, 3, 4, 5};
    });
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    final partner = ref.watch(partnerNameProvider);
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
            child: Text(existing == null ? 'Add a chore' : 'Edit chore', style: AppText.title),
          ),
          const SizedBox(height: 4),
          Text(
            partner == null
                ? 'Whoever does it marks it off.'
                : 'You and $partner both see it. Whoever does it marks it off and earns the gems.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          if (existing == null) ...[
            const FieldLabel('Quick add'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kSharedHabitTemplates)
                  HabitPill(
                    label: t.name,
                    selected: _name.text.trim() == t.name,
                    onTap: () => _useTemplate(t),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          const FieldLabel('Name'),
          AppTextField(
            controller: _name,
            hint: 'For example, Do the laundry',
            semanticLabel: 'Chore name',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxSharedName)],
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Icon'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in _kIconOrder)
                HabitIconChoice(
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
          const FieldLabel('How often'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HabitPill(
                label: 'Every day',
                selected: _kind == SharedKind.daily,
                onTap: () => _setKind(SharedKind.daily),
              ),
              HabitPill(
                label: 'Certain days',
                selected: _kind == SharedKind.weekdays,
                onTap: () => _setKind(SharedKind.weekdays),
              ),
              HabitPill(
                label: 'Every week',
                selected: _kind == SharedKind.weekly,
                onTap: () => _setKind(SharedKind.weekly),
              ),
              HabitPill(
                label: 'Every few days',
                selected: _kind == SharedKind.everyN,
                onTap: () => _setKind(SharedKind.everyN),
              ),
            ],
          ),
          if (_kind == SharedKind.weekdays) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  HabitDayChip(
                    letter: kDayLetters[d - 1],
                    name: kDayNames[d - 1],
                    on: _days.contains(d),
                    onTap: () => _toggleDay(d),
                  ),
              ],
            ),
          ],
          if (_kind == SharedKind.everyN) ...[
            const SizedBox(height: 12),
            _EveryStepper(
              days: _every,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _every = v);
              },
            ),
          ],
          if (_kind == SharedKind.weekly || _kind == SharedKind.everyN) ...[
            const SizedBox(height: 8),
            const Text('Counted from the last time it was done.', style: AppText.caption),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 20),
          ChunkyButton(
            label: existing == null ? 'Add chore' : 'Save',
            busy: _busy,
            onPressed: _valid ? _submit : null,
          ),
          if (existing != null) ...[
            const SizedBox(height: 10),
            ChunkyButton.secondary(
              label: 'Delete chore',
              icon: Icons.delete_outline_rounded,
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}

class _EveryStepper extends StatelessWidget {
  const _EveryStepper({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChunkyIconButton(
          icon: Icons.remove_rounded,
          semanticLabel: 'Fewer days',
          size: 52,
          kind: ChunkyKind.secondary,
          onPressed: days > kMinEveryDays ? () => onChanged(days - 1) : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              'Every $days days',
              textAlign: TextAlign.center,
              style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        ChunkyIconButton(
          icon: Icons.add_rounded,
          semanticLabel: 'More days',
          size: 52,
          onPressed: days < kMaxEveryDays ? () => onChanged(days + 1) : null,
        ),
      ],
    );
  }
}
