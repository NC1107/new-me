import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/skeletons.dart';
import 'big_number_stepper.dart';
import 'meal_estimate.dart';
import 'food_search.dart';
import 'log_chip.dart';
import 'meal_items.dart';

/// Builds the write for one attempt; the sheet supplies the idempotency key and the date.
typedef DraftBuilder = LogDraft Function(String clientOpId, String? localDate);

typedef LogCallback = Future<void> Function(
  DraftBuilder build, {
  required String added,
  String? confirm,
  List<MealItem>? libraryItems,
});

/// Logs several entries one after another, each with its own idempotency key.
typedef LogManyCallback = Future<void> Function(
  List<DraftBuilder> builds, {
  required String added,
  String? confirm,
  List<MealItem>? libraryItems,
});

const kMaxReps = 500;
const kMaxMinutes = 1440;
const kMaxPages = 2000;
const kMaxKcal = 10000;
const kMaxMacroGrams = 9999.9;

const kConfirmReps = 200;
const kConfirmPages = 300;
const kConfirmKcal = 3000;

const kPortions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// The unit of a push-up max test, which is recorded apart from the day's log.
const kMaxTestUnit = 'max';

int _capFor(String unit) => switch (unit) {
  'reps' || kMaxTestUnit => kMaxReps,
  'pages' => kMaxPages,
  _ => kMaxMinutes,
};

int? _confirmAbove(String unit) => switch (unit) {
  'reps' => kConfirmReps,
  'pages' => kConfirmPages,
  _ => null,
};

String _noun(String unit, int n) => switch (unit) {
  'reps' || kMaxTestUnit => n == 1 ? 'push-up' : 'push-ups',
  'pages' => n == 1 ? 'page' : 'pages',
  _ => n == 1 ? 'minute' : 'minutes',
};

/// How one unit of a quantity form behaves: where the number starts, how far - and + move it, and
/// which quick chips add to it.
class UnitSpec {
  const UnitSpec({
    required this.unit,
    required this.label,
    required this.start,
    required this.step,
    required this.chips,
    this.choices = const [],
    this.countLabel,
    this.caption,
    this.saveLabel,
  });

  final String unit;

  /// What the number counts, shown under it and on the toggle.
  final String label;
  final int start;
  final int step;
  final List<int> chips;

  /// Fixed amounts that set the number instead of adding to it, such as class lengths.
  final List<int> choices;

  /// What the number counts when that differs from the toggle's [label].
  final String? countLabel;

  /// Explains the unit under the quick chips.
  final String? caption;

  /// The save button's text, when it is not "Save".
  final String? saveLabel;
}

/// Pushups, reading and yoga: one whole number, in one of a few units.
class QuantityPane extends StatefulWidget {
  const QuantityPane({
    super.key,
    required this.type,
    required this.units,
    required this.busy,
    required this.failed,
    required this.onLog,
    this.onMaxTest,
    this.initialUnit,
  });

  final String type;
  final List<UnitSpec> units;
  final bool busy;
  final bool failed;
  final LogCallback onLog;

  /// Saves a max test; only a pane that offers [kMaxTestUnit] needs it.
  final Future<void> Function(int reps)? onMaxTest;

  /// The unit to open on; the first one when null or unknown.
  final String? initialUnit;

  @override
  State<QuantityPane> createState() => _QuantityPaneState();
}

class _QuantityPaneState extends State<QuantityPane> {
  late UnitSpec _spec =
      widget.units.where((u) => u.unit == widget.initialUnit).firstOrNull ?? widget.units.first;
  late final _field = TextEditingController(text: '${_spec.start}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _unit => _spec.unit;

  int? get _quantity => int.tryParse(_field.text);

  String? get _fieldError {
    final q = _quantity;
    if (_field.text.isEmpty || q == null) return null;
    if (q > _capFor(_unit)) return 'At most ${_capFor(_unit).formatted} ${_noun(_unit, 2)}';
    return null;
  }

  bool get _valid => _quantity != null && _quantity! > 0 && _fieldError == null;

  void _set(int value) {
    final next = value.clamp(0, _capFor(_unit));
    setState(() => _field.text = '$next');
  }

  void _pickUnit(UnitSpec spec) {
    if (spec.unit == _unit) return;
    setState(() {
      _spec = spec;
      _field.text = '${spec.start}';
    });
  }

  void _log(int quantity) {
    if (_unit == kMaxTestUnit) {
      widget.onMaxTest?.call(quantity);
      return;
    }
    final limit = _confirmAbove(_unit);
    widget.onLog(
      (id, date) => ActivityDraft(
        clientOpId: id,
        type: widget.type,
        quantity: quantity,
        unit: _unit,
        date: date,
      ),
      added: _unit == 'reps'
          ? 'Added $quantity ${_noun(_unit, quantity)}'
          : 'Added $quantity ${shortUnit(_unit)}',
      confirm: limit != null && quantity > limit
          ? 'That is ${quantity.formatted} ${_noun(_unit, quantity)} in one go. Log it?'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quantity ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.units.length > 1) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final spec in widget.units)
                LogChip(
                  label: spec.label,
                  selected: spec.unit == _unit,
                  onTap: () => _pickUnit(spec),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        BigNumberStepper(
          controller: _field,
          unitLabel:
              _spec.countLabel ??
              (widget.units.length > 1 ? _spec.label.toLowerCase() : _spec.label),
          errorText: _fieldError,
          onChanged: (_) => setState(() {}),
          onMinus: q > 0 && !widget.busy ? () => _set(q - _spec.step) : null,
          onPlus: q < _capFor(_unit) && !widget.busy ? () => _set(q + _spec.step) : null,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in _spec.choices)
              LogChip(label: '$v', selected: q == v, enabled: !widget.busy, onTap: () => _set(v)),
            for (final v in _spec.chips)
              LogChip(
                label: '+$v',
                enabled: !widget.busy && q < _capFor(_unit),
                onTap: () => _set(q + v),
              ),
          ],
        ),
        if (_spec.caption case final caption?) ...[
          const SizedBox(height: 14),
          Text(caption, textAlign: TextAlign.center, style: AppText.caption),
        ],
        const SizedBox(height: 24),
        ChunkyButton(
          label: widget.failed ? 'Try again' : _spec.saveLabel ?? 'Save',
          busy: widget.busy,
          onPressed: _valid && !widget.busy ? () => _log(_quantity!) : null,
        ),
      ],
    );
  }
}

class MealPane extends StatefulWidget {
  const MealPane({
    super.key,
    required this.recent,
    required this.busy,
    required this.failed,
    required this.onLog,
    required this.onLogMany,
    this.canEstimate = false,
    this.autofocusSearch = false,
  });

  /// Shows "Describe it"; the server switches it on with its Claude key. Searching the food
  /// library needs no key, so it is always there.
  final bool canEstimate;

  /// Opens with the food search focused, for the Food tab's "Log a meal".
  final bool autofocusSearch;

  final Future<List<RecentMeal>> recent;
  final bool busy;
  final bool failed;
  final LogCallback onLog;
  final LogManyCallback onLogMany;

  @override
  State<MealPane> createState() => _MealPaneState();
}

class _MealPaneState extends State<MealPane> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  double _portion = 1;
  bool _more = false;
  bool _estimating = false;
  MealEstimate? _estimate;
  final List<MealEntry> _entries = [];

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _fiber]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  int _scaleKcal(int v) => (v * _portion).round();

  num _scaleMacro(num v) => (v * _portion * 10).round() / 10;

  int get _kcalValue => int.tryParse(_kcal.text) ?? 0;

  num _grams(TextEditingController c) => num.tryParse(c.text) ?? 0;

  String? get _kcalError =>
      _scaleKcal(_kcalValue) > kMaxKcal ? 'At most ${kMaxKcal.formatted} kcal' : null;

  String? _gramsError(TextEditingController c) =>
      _scaleMacro(_grams(c)) > kMaxMacroGrams ? 'Too large' : null;

  bool get _valid =>
      !_estimating &&
      _kcalValue > 0 &&
      _kcalError == null &&
      [_protein, _carbs, _fat, _fiber].every((c) => _gramsError(c) == null);

  static String _gramsText(num v) => v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);

  /// Adds the itemized result to what is already listed, since a food the databases lack is
  /// often described after the rest were picked from search. A server without itemizing answers
  /// one meal, which fills the form as it always did.
  void _applyBreakdown(MealBreakdown b) {
    if (b.items.isEmpty) {
      _applyEstimate(b.legacy);
      return;
    }
    setState(() {
      _entries.addAll(b.items.map(MealEntry.new));
      _estimate = null;
    });
  }

  void _addFood(SavedFood food) => setState(() => _entries.add(MealEntry(MealItem.fromFood(food))));

  List<MealItem> get _items => [for (final e in _entries) e.item];

  MealDraft Function(String, String?) _draftFor(
    String name,
    int kcal,
    num p,
    num c,
    num f,
    num fi,
  ) =>
      (id, date) => MealDraft(
        clientOpId: id,
        name: name,
        kcal: kcal,
        protein: p,
        carbs: c,
        fat: f,
        fiber: fi,
        date: date,
      );

  void _logOne() {
    final items = _items;
    final t = mealTotals(items);
    final name = joinedMealName(items);
    widget.onLog(
      _draftFor(name, t.kcal, t.protein, t.carbs, t.fat, t.fiber),
      added: 'Added $name',
      confirm: t.kcal > kConfirmKcal ? _confirmCopy(t.kcal) : null,
      libraryItems: items,
    );
  }

  void _logSeparately() {
    final items = _items;
    final total = mealTotals(items).kcal;
    widget.onLogMany(
      [
        for (final i in items)
          _draftFor(
            i.name.trim().isEmpty ? 'Meal' : i.name.trim(),
            i.kcal,
            i.protein,
            i.carbs,
            i.fat,
            i.fiber,
          ),
      ],
      added: 'Added ${items.length} meals',
      confirm: total > kConfirmKcal ? _confirmCopy(total) : null,
      libraryItems: items,
    );
  }

  /// Fills the form from an estimate. Nothing is logged: the person checks and saves.
  void _applyEstimate(MealEstimate e) {
    setState(() {
      _estimate = e;
      _name.text = e.name;
      _kcal.text = '${e.kcal}';
      _protein.text = _gramsText(e.protein);
      _carbs.text = _gramsText(e.carbs);
      _fat.text = _gramsText(e.fat);
      _fiber.text = _gramsText(e.fiber);
      _more = _more || e.fiber > 0;
      _portion = 1;
    });
  }

  void _logRecent(RecentMeal meal) {
    final kcal = _scaleKcal(meal.kcal);
    widget.onLog(
      (id, date) => MealDraft(
        clientOpId: id,
        name: meal.name,
        kcal: kcal,
        protein: _scaleMacro(meal.protein),
        carbs: _scaleMacro(meal.carbs),
        fat: _scaleMacro(meal.fat),
        fiber: _scaleMacro(meal.fiber),
        date: date,
      ),
      added: 'Added ${meal.name}',
      confirm: kcal > kConfirmKcal ? _confirmCopy(kcal) : null,
    );
  }

  String _confirmCopy(int kcal) => 'That is ${kcal.formatted} kcal in one meal. Log it?';

  void _logForm() {
    final kcal = _scaleKcal(_kcalValue);
    final name = _name.text.trim().isEmpty ? 'Meal' : _name.text.trim();
    widget.onLog(
      (id, date) => MealDraft(
        clientOpId: id,
        name: name,
        kcal: kcal,
        protein: _scaleMacro(_grams(_protein)),
        carbs: _scaleMacro(_grams(_carbs)),
        fat: _scaleMacro(_grams(_fat)),
        fiber: _scaleMacro(_grams(_fiber)),
        date: date,
      ),
      added: 'Added $name',
      confirm: kcal > kConfirmKcal ? _confirmCopy(kcal) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canEstimate) ...[
          MealEstimateBar(
            onEstimate: _applyBreakdown,
            onBusyChanged: (busy) => setState(() => _estimating = busy),
          ),
          const SizedBox(height: 12),
        ],
        FoodSearchBox(
          onPick: _addFood,
          enabled: !widget.busy,
          autofocus: widget.autofocusSearch,
          onEnterByHand: _entries.isEmpty ? _nameFocus.requestFocus : null,
        ),
        const SizedBox(height: 16),
        if (_entries.isNotEmpty)
          ItemizedMeal(
            entries: _entries,
            busy: widget.busy,
            onChanged: () => setState(() {}),
            onLogOne: _logOne,
            onLogSeparately: _logSeparately,
            onClear: () => setState(_entries.clear),
          )
        else
          ..._manualForm(context),
      ],
    );
  }

  List<Widget> _manualForm(BuildContext context) {
    return [
      if (_estimate case final estimate?) ...[
        EstimateNote(estimate: estimate),
        const SizedBox(height: 16),
      ],
      FutureBuilder<List<RecentMeal>>(
        future: widget.recent,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  SkeletonBlock(width: 96, height: 44, radius: 22),
                  SizedBox(width: 8),
                  SkeletonBlock(width: 120, height: 44, radius: 22),
                ],
              ),
            );
          }
          final meals = snapshot.data ?? const <RecentMeal>[];
          if (meals.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Recent meals, tap to log'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final meal in meals)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: LogChip(
                          label: meal.name,
                          enabled: !widget.busy,
                          onTap: () => _logRecent(meal),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      const FieldLabel('Name'),
      AppTextField(
        controller: _name,
        focusNode: _nameFocus,
        hint: 'What was it? (optional)',
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(80)],
      ),
      const SizedBox(height: 12),
      const FieldLabel('Calories'),
      AppTextField(
        controller: _kcal,
        hint: 'kcal',
        keyboardType: TextInputType.number,
        errorText: _kcalError,
        onChanged: (_) => setState(() {}),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _gramsField('Protein', _protein)),
          const SizedBox(width: 8),
          Expanded(child: _gramsField('Carbs', _carbs)),
          const SizedBox(width: 8),
          Expanded(child: _gramsField('Fat', _fat)),
        ],
      ),
      if (_more) ...[const SizedBox(height: 12), _gramsField('Fiber', _fiber)],
      Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          child: GestureDetector(
            onTap: () => setState(() => _more = !_more),
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(
                widthFactor: 1,
                alignment: Alignment.centerLeft,
                child: Text(
                  _more ? 'Less' : 'More',
                  style: AppText.label.copyWith(color: context.accentText),
                ),
              ),
            ),
          ),
        ),
      ),
      const FieldLabel('Portion'),
      _portionChips(context),
      if (_portion != 1 && _kcalValue > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Logs ${_scaleKcal(_kcalValue).formatted} kcal',
            style: AppText.label.copyWith(color: kInkSecondary),
          ),
        ),
      const SizedBox(height: 20),
      ChunkyButton(
        label: widget.failed ? 'Try again' : 'Save',
        busy: widget.busy,
        onPressed: _valid && !widget.busy ? _logForm : null,
      ),
    ];
  }

  Widget _portionChips(BuildContext context) {
    final chips = [
      for (final p in kPortions)
        LogChip(
          label: p.toString().replaceFirst(RegExp(r'\.0$'), ''),
          selected: p == _portion,
          compact: true,
          onTap: () => setState(() => _portion = p),
        ),
    ];
    // Six chips share one row until Dynamic Type makes them too wide for it.
    final fitsInRow = MediaQuery.textScalerOf(context).scale(15) <= 19;
    if (!fitsInRow) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: chips[i]),
        ],
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
        onChanged: (_) => setState(() {}),
        inputFormatters: [_gramsFormatter],
      ),
    ],
  );
}

final _gramsPattern = RegExp(r'^\d{0,4}(\.\d?)?$');

final _gramsFormatter = TextInputFormatter.withFunction(
  (old, next) => _gramsPattern.hasMatch(next.text) ? next : old,
);
