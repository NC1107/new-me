import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/segmented.dart';
import '../../widgets/skeletons.dart';

/// Builds the write for one attempt; the sheet supplies the idempotency key and the date.
typedef DraftBuilder = LogDraft Function(String clientOpId, String? localDate);

typedef LogCallback = Future<void> Function(
  DraftBuilder build, {
  required String added,
  String? confirm,
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

int _capFor(String unit) => switch (unit) {
  'reps' => kMaxReps,
  'pages' => kMaxPages,
  _ => kMaxMinutes,
};

int? _confirmAbove(String unit) => switch (unit) {
  'reps' => kConfirmReps,
  'pages' => kConfirmPages,
  _ => null,
};

String _noun(String unit, int n) => switch (unit) {
  'reps' => n == 1 ? 'pushup' : 'pushups',
  'pages' => n == 1 ? 'page' : 'pages',
  _ => n == 1 ? 'minute' : 'minutes',
};

/// Pushups, reading and yoga: one whole number, in one of a few units.
class QuantityPane extends StatefulWidget {
  const QuantityPane({
    super.key,
    required this.type,
    required this.units,
    required this.busy,
    required this.failed,
    required this.onLog,
    this.quickValues = const [],
  });

  final String type;
  final List<(String unit, String label)> units;
  final List<int> quickValues;
  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<QuantityPane> createState() => _QuantityPaneState();
}

class _QuantityPaneState extends State<QuantityPane> {
  final _field = TextEditingController();
  late String _unit = widget.units.first.$1;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _quantity => int.tryParse(_field.text);

  String? get _fieldError {
    final q = _quantity;
    if (_field.text.isEmpty || q == null) return null;
    if (q > _capFor(_unit)) return 'At most ${_capFor(_unit).formatted} ${_noun(_unit, 2)}';
    return null;
  }

  bool get _valid => _quantity != null && _quantity! > 0 && _fieldError == null;

  void _log(int quantity) {
    final limit = _confirmAbove(_unit);
    widget.onLog(
      (id, date) => ActivityDraft(
        clientOpId: id,
        type: widget.type,
        quantity: quantity,
        unit: _unit,
        localDate: date,
      ),
      added: 'Added $quantity${_unit == 'reps' ? '' : ' ${shortUnit(_unit)}'}',
      confirm: limit != null && quantity > limit
          ? 'That is ${quantity.formatted} ${_noun(_unit, quantity)} in one go. Log it?'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.units.length > 1) ...[
          Segmented<String>(
            options: [for (final (unit, label) in widget.units) (unit, label)],
            selected: _unit,
            onChanged: (v) => setState(() => _unit = v),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.quickValues.isNotEmpty) ...[
          const FieldLabel('Quick add'),
          Row(
            children: [
              for (final v in widget.quickValues) ...[
                Expanded(
                  child: ChipButton(
                    label: '$v',
                    enabled: !widget.busy,
                    fill: true,
                    onTap: () => _log(v),
                  ),
                ),
                if (v != widget.quickValues.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
        FieldLabel(widget.quickValues.isEmpty ? _label : 'Custom'),
        AppTextField(
          controller: _field,
          hint: _hint,
          keyboardType: TextInputType.number,
          errorText: _fieldError,
          onChanged: (_) => setState(() {}),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: widget.failed ? 'Try again' : 'Save',
          enabled: _valid && !widget.busy,
          busy: widget.busy,
          onTap: () => _log(_quantity!),
        ),
      ],
    );
  }

  String get _label => widget.units.length > 1 ? _unitLabel : 'Amount';

  String get _unitLabel => widget.units.firstWhere((u) => u.$1 == _unit).$2;

  String get _hint => switch (_unit) {
    'reps' => 'Reps',
    'pages' => 'Pages read',
    _ => 'Minutes',
  };
}

class MealPane extends StatefulWidget {
  const MealPane({
    super.key,
    required this.recent,
    required this.busy,
    required this.failed,
    required this.onLog,
  });

  final Future<List<RecentMeal>> recent;
  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<MealPane> createState() => _MealPaneState();
}

class _MealPaneState extends State<MealPane> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  double _portion = 1;
  bool _more = false;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _fiber]) {
      c.dispose();
    }
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
      _kcalValue > 0 &&
      _kcalError == null &&
      [_protein, _carbs, _fat, _fiber].every((c) => _gramsError(c) == null);

  void _logRecent(RecentMeal meal) {
    final kcal = _scaleKcal(meal.kcal);
    widget.onLog(
      (id, date) => MealDraft(
        clientOpId: id,
        name: meal.name,
        kcal: kcal,
        proteinG: _scaleMacro(meal.proteinG),
        carbsG: _scaleMacro(meal.carbsG),
        fatG: _scaleMacro(meal.fatG),
        fiberG: _scaleMacro(meal.fiberG),
        localDate: date,
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
        proteinG: _scaleMacro(_grams(_protein)),
        carbsG: _scaleMacro(_grams(_carbs)),
        fatG: _scaleMacro(_grams(_fat)),
        fiberG: _scaleMacro(_grams(_fiber)),
        localDate: date,
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
        FutureBuilder<List<RecentMeal>>(
          future: widget.recent,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SkeletonBlock(width: 96, height: 38, radius: 19),
                    SizedBox(width: 8),
                    SkeletonBlock(width: 120, height: 38, radius: 19),
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
                  const FieldLabel('Recent meals - tap to log'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final meal in meals)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: ChipButton(
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
        const FieldLabel('Portion'),
        Segmented<double>(
          options: [for (final p in kPortions) (p, p.toString().replaceFirst(RegExp(r'\.0$'), ''))],
          selected: _portion,
          onChanged: (v) => setState(() => _portion = v),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Name'),
        AppTextField(
          controller: _name,
          hint: 'What was it? (optional)',
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
          child: TextButton(
            onPressed: () => setState(() => _more = !_more),
            style: TextButton.styleFrom(foregroundColor: kFgSecondary, padding: EdgeInsets.zero),
            child: Text(_more ? 'Less' : 'More', style: const TextStyle(fontSize: 13)),
          ),
        ),
        if (_portion != 1 && _kcalValue > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Logs ${_scaleKcal(_kcalValue).formatted} kcal',
              style: const TextStyle(
                color: kFgSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: widget.failed ? 'Try again' : 'Save',
          enabled: _valid && !widget.busy,
          busy: widget.busy,
          onTap: _logForm,
        ),
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
