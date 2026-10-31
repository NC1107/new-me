import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/foods.dart';
import '../../state/log_actions.dart';
import '../../state/today.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../util/time_format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../log/log_chip.dart';
import '../log/log_panes.dart';
import '../log/log_sheet.dart' show LogErrorLine;
import 'meal_actions.dart';

/// The multipliers for "I ate half" or "I ate double". Each applies to the meal as it was
/// opened, so tapping 2x after 0.5x gives double, not half of double.
const kEditScales = [0.5, 1.5, 2.0];

String _scaleLabel(double s) => s.toString().replaceFirst(RegExp(r'\.0$'), '');

/// Opens the editor for one meal. Resolves true when the meal was saved or deleted, so a list
/// holding its own copy can reload. [onUndone] runs if a delete is undone.
Future<bool> showEditMealSheet(BuildContext context, MealLog meal, {VoidCallback? onUndone}) async {
  final messenger = ScaffoldMessenger.of(context);
  final changed = await showAppSheet<bool>(
    context,
    builder: (_) => EditMealSheet(meal: meal, messenger: messenger, onUndone: onUndone),
  );
  return changed ?? false;
}

class EditMealSheet extends ConsumerStatefulWidget {
  const EditMealSheet({super.key, required this.meal, required this.messenger, this.onUndone});

  final MealLog meal;

  /// The messenger of the screen below, so "Updated" and "Deleted" outlive this sheet.
  final ScaffoldMessengerState messenger;
  final VoidCallback? onUndone;

  @override
  ConsumerState<EditMealSheet> createState() => _EditMealSheetState();
}

class _EditMealSheetState extends ConsumerState<EditMealSheet> {
  late final _name = TextEditingController(text: widget.meal.name);
  late final _kcal = TextEditingController(text: '${widget.meal.kcal}');
  late final _protein = TextEditingController(text: gramsText(widget.meal.protein));
  late final _carbs = TextEditingController(text: gramsText(widget.meal.carbs));
  late final _fat = TextEditingController(text: gramsText(widget.meal.fat));
  late final _fiber = TextEditingController(text: gramsText(widget.meal.fiber));
  late String _day = _meal.localDate;
  late TimeOfDay _time = _initialTime;
  double? _scale;
  bool _busy = false;
  String? _error;

  MealLog get _meal => widget.meal;

  TimeOfDay get _initialTime => TimeOfDay.fromDateTime(_meal.loggedAt.toLocal());

  DateTime get _when {
    final d = parseLocalDate(_day);
    return DateTime(d.year, d.month, d.day, _time.hour, _time.minute);
  }

  bool get _whenChanged => _day != _meal.localDate || _time != _initialTime;

  bool get _inFuture => _whenChanged && _when.isAfter(ref.read(clockProvider)());

  /// The days the meal may sit on: today, and yesterday while its window is open or it is there.
  List<String> get _days {
    final today = ref.watch(todayProvider).value?.data;
    final localToday = today?.localToday;
    if (localToday == null) return [_meal.localDate];
    final yesterday = previousDate(localToday);
    final windowOpen =
        today?.backdateUntil != null && ref.read(clockProvider)().isBefore(today!.backdateUntil!);
    return [if (windowOpen || _meal.localDate == yesterday) yesterday, localToday];
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _fiber]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _editable {
    final today = ref.watch(todayProvider).value?.data;
    return mealIsEditable(
      meal: _meal,
      localToday: today?.localToday,
      backdateUntil: today?.backdateUntil,
      now: ref.read(clockProvider)(),
    );
  }

  int get _kcalValue => int.tryParse(_kcal.text) ?? 0;

  num _grams(TextEditingController c) => num.tryParse(c.text) ?? 0;

  String? get _kcalError => _kcalValue > kMaxKcal ? 'At most ${kMaxKcal.formatted} kcal' : null;

  String? _gramsError(TextEditingController c) => _grams(c) > kMaxMacroGrams ? 'Too large' : null;

  String? get _nameError => _name.text.trim().isEmpty ? 'Give it a name' : null;

  bool get _valid =>
      _nameError == null &&
      !_inFuture &&
      _kcalValue > 0 &&
      _kcalError == null &&
      [_protein, _carbs, _fat, _fiber].every((c) => _gramsError(c) == null);

  static bool _sameGrams(num a, num b) => (a * 10).round() == (b * 10).round();

  /// Only what differs from the meal as opened, so a save never rewrites a number the person
  /// did not touch.
  MealEdit get _edit {
    final name = _name.text.trim();
    return MealEdit(
      name: name == _meal.name ? null : name,
      kcal: _kcalValue == _meal.kcal ? null : _kcalValue,
      protein: _sameGrams(_grams(_protein), _meal.protein) ? null : _grams(_protein),
      carbs: _sameGrams(_grams(_carbs), _meal.carbs) ? null : _grams(_carbs),
      fat: _sameGrams(_grams(_fat), _meal.fat) ? null : _grams(_fat),
      fiber: _sameGrams(_grams(_fiber), _meal.fiber) ? null : _grams(_fiber),
      loggedAt: _whenChanged ? _when.toUtc() : null,
    );
  }

  void _applyScale(double factor) {
    final selected = _scale == factor;
    final f = selected ? 1.0 : factor;
    setState(() {
      _scale = selected ? null : factor;
      _kcal.text = '${scaleKcal(_meal.kcal, f)}';
      _protein.text = gramsText(scaleMacro(_meal.protein, f));
      _carbs.text = gramsText(scaleMacro(_meal.carbs, f));
      _fat.text = gramsText(scaleMacro(_meal.fat, f));
      _fiber.text = gramsText(scaleMacro(_meal.fiber, f));
      _error = null;
    });
  }

  void _typed() => setState(() {
    _scale = null;
    _error = null;
  });

  Future<void> _save() async {
    final edit = _edit;
    if (_busy || edit.isEmpty || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = edit.name ?? _meal.name;
    try {
      await ref.read(logActionsProvider).updateMeal(_meal, edit);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.kind == ApiErrorKind.dateClosed
            ? 'That day is closed, so this meal can no longer be edited.'
            : errorCopy(e);
      });
      return;
    }
    HapticFeedback.mediumImpact();
    widget.messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Updated $name')));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() {
      _time = picked;
      _error = null;
    });
  }

  Future<void> _logAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await logMealAgain(widget.messenger, ref.read(logActionsProvider), _meal);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveAsFood() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(logActionsProvider)
          .saveFood(
            SavedFood(
              name: _meal.name,
              servingText: '1 meal',
              kcal: _meal.kcal,
              protein: _meal.protein.toDouble(),
              carbs: _meal.carbs.toDouble(),
              fat: _meal.fat.toDouble(),
              fiber: _meal.fiber.toDouble(),
            ),
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorCopy(e);
      });
      return;
    }
    ref.invalidate(foodLibraryProvider);
    HapticFeedback.mediumImpact();
    widget.messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Saved ${_meal.name} to My foods')));
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final actions = ref.read(logActionsProvider);
    Navigator.of(context).pop(true);
    await deleteMealWithUndo(widget.messenger, actions, _meal, onUndone: widget.onUndone);
  }

  @override
  Widget build(BuildContext context) {
    final editable = _editable;
    final palette = questPalette('meals_logged');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                    child: Icon(questIcon('meals_logged'), size: 24, color: palette.lip),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(editable ? 'Edit meal' : 'Meal', style: AppText.title),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (editable) ..._form(context) else ..._readOnly(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _readOnly() {
    final rows = [
      ('Calories', '${_meal.kcal.formatted} kcal'),
      ('Protein', '${_meal.protein.formatted} g'),
      ('Carbs', '${_meal.carbs.formatted} g'),
      ('Fat', '${_meal.fat.formatted} g'),
      ('Fiber', '${_meal.fiber.formatted} g'),
    ];
    return [
      Text(_meal.name, style: AppText.headline),
      const SizedBox(height: 12),
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: AppText.body.copyWith(color: kInkSecondary)),
              ),
              Text(value, style: AppText.tabular(AppText.label)),
            ],
          ),
        ),
      const SizedBox(height: 12),
      Text(
        'This day is closed, so its meals can no longer be changed.',
        style: AppText.label.copyWith(color: kInkSecondary),
      ),
      const SizedBox(height: 20),
      ..._reuseActions(),
      const SizedBox(height: 4),
      ChunkyButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop(false)),
    ];
  }

  List<Widget> _form(BuildContext context) {
    return [
      const FieldLabel('Name'),
      AppTextField(
        controller: _name,
        hint: 'What was it?',
        textCapitalization: TextCapitalization.sentences,
        errorText: _nameError,
        onChanged: (_) => _typed(),
        inputFormatters: [LengthLimitingTextInputFormatter(80)],
      ),
      const SizedBox(height: 12),
      const FieldLabel('Calories'),
      AppTextField(
        controller: _kcal,
        hint: 'kcal',
        keyboardType: TextInputType.number,
        errorText: _kcalError,
        onChanged: (_) => _typed(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
      ),
      const SizedBox(height: 12),
      _macroFields(context),
      const SizedBox(height: 16),
      const FieldLabel('Scale'),
      _scaleChips(),
      const SizedBox(height: 16),
      const FieldLabel('When'),
      _whenRow(),
      if (_inFuture) ...[
        const SizedBox(height: 6),
        Text(
          'That time has not happened yet.',
          style: AppText.caption.copyWith(color: kDangerText),
        ),
      ],
      const SizedBox(height: 20),
      ChunkyButton(
        label: _error != null ? 'Try again' : 'Save',
        busy: _busy,
        onPressed: _valid && !_edit.isEmpty && !_busy ? _save : null,
      ),
      if (_error != null) ...[const SizedBox(height: 12), LogErrorLine(message: _error!)],
      const SizedBox(height: 8),
      ..._reuseActions(),
      TextButton.icon(
        onPressed: _busy ? null : _delete,
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
        label: const Text('Delete meal'),
        style: TextButton.styleFrom(
          foregroundColor: kDangerText,
          minimumSize: const Size.fromHeight(48),
          textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ];
  }

  /// Using the meal again: a copy for today, or a saved food that search finds next time.
  List<Widget> _reuseActions() => [
    ChunkyButton.secondary(
      label: 'Log again today',
      icon: Icons.replay_rounded,
      onPressed: _busy ? null : _logAgain,
    ),
    TextButton.icon(
      onPressed: _busy ? null : _saveAsFood,
      icon: const Icon(Icons.bookmark_border_rounded, size: 20),
      label: const Text('Save to My foods'),
      style: TextButton.styleFrom(
        foregroundColor: kInkSecondary,
        minimumSize: const Size.fromHeight(48),
        textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  ];

  Widget _whenRow() {
    final days = _days;
    final localToday = ref.watch(todayProvider).value?.data.localToday;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (days.length > 1)
          for (final d in days)
            LogChip(
              label: d == localToday ? 'Today' : 'Yesterday',
              selected: d == _day,
              onTap: () => setState(() {
                _day = d;
                _error = null;
                // Moving a late-night meal onto today would otherwise land in the future.
                final now = ref.read(clockProvider)();
                if (_when.isAfter(now)) _time = TimeOfDay.fromDateTime(now);
              }),
            ),
        LogChip(
          label: formatClock(DateTime(2000, 1, 1, _time.hour, _time.minute)),
          semanticLabel: 'Time eaten',
          onTap: _pickTime,
        ),
      ],
    );
  }

  Widget _macroFields(BuildContext context) {
    final protein = _gramsField('Protein', _protein);
    final carbs = _gramsField('Carbs', _carbs);
    final fat = _gramsField('Fat', _fat);
    final fiber = _gramsField('Fiber', _fiber);
    // Protein, carbs and fat share a row until Dynamic Type makes their labels too wide for it.
    final fitsInRow = MediaQuery.textScalerOf(context).scale(15) <= 19;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fitsInRow)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: protein),
              const SizedBox(width: 8),
              Expanded(child: carbs),
              const SizedBox(width: 8),
              Expanded(child: fat),
            ],
          )
        else ...[
          protein,
          const SizedBox(height: 12),
          carbs,
          const SizedBox(height: 12),
          fat,
        ],
        const SizedBox(height: 12),
        fiber,
      ],
    );
  }

  Widget _gramsField(String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel('$label (g)'),
      AppTextField(
        controller: controller,
        hint: '0',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        errorText: _gramsError(controller),
        onChanged: (_) => _typed(),
        inputFormatters: [gramsInputFormatter],
      ),
    ],
  );

  Widget _scaleChips() => Row(
    children: [
      for (final (i, s) in kEditScales.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: LogChip(
            label: '${_scaleLabel(s)}x',
            semanticLabel: '${_scaleLabel(s)} times',
            selected: s == _scale,
            compact: true,
            onTap: () => _applyScale(s),
          ),
        ),
      ],
    ],
  );
}
