import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import 'me_support.dart';

final _decimal = TextInputFormatter.withFunction(
  (old, next) => RegExp(r'^\d{0,4}(\.\d?)?$').hasMatch(next.text) ? next : old,
);

class _ServingRow {
  _ServingRow([FoodServing? s])
    : label = TextEditingController(text: s?.text ?? ''),
      grams = TextEditingController(text: s == null ? '' : _g(s.grams));

  final TextEditingController label;
  final TextEditingController grams;

  void dispose() {
    label.dispose();
    grams.dispose();
  }
}

String _g(num v) => v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);

/// Adds a food from a label, or edits a saved one: its serving, its nutrients and any other
/// servings with their weights. Nutrients are per the main serving.
class FoodEditPage extends ConsumerStatefulWidget {
  const FoodEditPage({super.key, this.food});

  /// Null starts a new food.
  final SavedFood? food;

  @override
  ConsumerState<FoodEditPage> createState() => _FoodEditPageState();
}

class _FoodEditPageState extends ConsumerState<FoodEditPage> {
  late final SavedFood? _food = widget.food;
  late final _name = TextEditingController(text: _food?.name ?? '');
  late final _brand = TextEditingController(text: _food?.brand ?? '');
  late final _serving = TextEditingController(text: _food?.servingText ?? '');
  late final _servingGrams = TextEditingController(
    text: (_food?.servingGrams ?? 0) > 0 ? _g(_food!.servingGrams) : '',
  );
  late final _kcal = TextEditingController(text: _food == null ? '' : '${_food.kcal}');
  late final _protein = TextEditingController(text: _food == null ? '' : _g(_food.protein));
  late final _carbs = TextEditingController(text: _food == null ? '' : _g(_food.carbs));
  late final _fat = TextEditingController(text: _food == null ? '' : _g(_food.fat));
  late final _fiber = TextEditingController(text: _food == null ? '' : _g(_food.fiber));
  late final List<_ServingRow> _alts = [
    for (final s in _food?.servings ?? const <FoodServing>[]) _ServingRow(s),
  ];
  bool _saving = false;
  String? _error;

  List<TextEditingController> get _all => [
    _name,
    _brand,
    _serving,
    _servingGrams,
    _kcal,
    _protein,
    _carbs,
    _fat,
    _fiber,
  ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    for (final a in _alts) {
      a.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _serving.text.trim().isNotEmpty &&
      (int.tryParse(_kcal.text.trim()) ?? -1) >= 0 &&
      _kcal.text.trim().isNotEmpty &&
      (int.tryParse(_kcal.text.trim()) ?? 0) <= 10000;

  SavedFood _build() => SavedFood(
    id: _food?.id,
    name: _name.text.trim(),
    brand: _brand.text.trim(),
    servingText: _serving.text.trim(),
    servingGrams: _num(_servingGrams),
    kcal: int.parse(_kcal.text.trim()),
    protein: _num(_protein),
    carbs: _num(_carbs),
    fat: _num(_fat),
    fiber: _num(_fiber),
    source: _food?.source ?? FoodSource.manual,
    sourceId: _food?.sourceId ?? '',
    servings: [
      for (final a in _alts)
        if (a.label.text.trim().isNotEmpty && _num(a.grams) > 0)
          FoodServing(text: a.label.text.trim(), grams: _num(a.grams)),
    ],
  );

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  Future<void> _save() => _run(() async {
    final actions = ref.read(logActionsProvider);
    final food = _build();
    if (_food?.id case final id?) {
      await actions.updateFood(id, food);
    } else {
      await actions.saveFood(food);
    }
  });

  Future<void> _delete() async {
    final id = _food?.id;
    if (id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete this food?',
      message: '${_food?.title} will be removed from My foods for both of you. Past meals stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await _run(() => ref.read(logActionsProvider).deleteFood(id));
  }

  Widget _field(
    String label,
    TextEditingController c,
    String hint, {
    bool grams = false,
    bool whole = false,
    int? max,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      AppTextField(
        controller: c,
        hint: hint,
        semanticLabel: label,
        keyboardType: grams || whole ? TextInputType.numberWithOptions(decimal: grams) : null,
        textCapitalization: grams || whole ? TextCapitalization.none : TextCapitalization.sentences,
        inputFormatters: [
          if (grams) _decimal,
          if (whole) FilteringTextInputFormatter.digitsOnly,
          if (whole) LengthLimitingTextInputFormatter(5),
          if (!grams && !whole) LengthLimitingTextInputFormatter(max ?? 80),
        ],
        onChanged: (_) => setState(() {}),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isNew = _food == null;
    return PageScaffold(
      title: isNew ? 'New food' : 'Edit food',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) SaveError(_error!),
          ChunkyButton(
            label: _error != null ? 'Try again' : 'Save',
            busy: _saving,
            onPressed: _valid && !_saving ? _save : null,
          ),
        ],
      ),
      children: [
        _field('Name', _name, 'Apple'),
        const SizedBox(height: 14),
        _field('Brand (optional)', _brand, 'Chomps', max: 40),
        const SizedBox(height: 14),
        _field('Serving', _serving, '1 medium (182 g)', max: 60),
        const SizedBox(height: 14),
        _field('Serving weight (g)', _servingGrams, 'Optional', grams: true),
        const SizedBox(height: 14),
        Text(
          'Numbers below are for one serving.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _field('Calories', _kcal, 'kcal', whole: true),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field('Protein (g)', _protein, '0', grams: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('Carbs (g)', _carbs, '0', grams: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('Fat (g)', _fat, '0', grams: true)),
          ],
        ),
        const SizedBox(height: 14),
        _field('Fiber (g)', _fiber, '0', grams: true),
        const SizedBox(height: 20),
        const FieldLabel('Other servings'),
        for (final (i, alt) in _alts.indexed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: alt.label,
                  hint: '1 cup sliced',
                  semanticLabel: 'Serving ${i + 1} name',
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: alt.grams,
                  hint: 'g',
                  semanticLabel: 'Serving ${i + 1} weight in grams',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimal],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Semantics(
                button: true,
                label: 'Remove serving ${i + 1}',
                excludeSemantics: true,
                child: IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => setState(() => _alts.removeAt(i).dispose()),
                  icon: const Icon(Icons.close_rounded, color: kInkSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_alts.length < 8)
          ChunkyButton.secondary(
            label: 'Add a serving',
            icon: Icons.add_rounded,
            onPressed: () => setState(() => _alts.add(_ServingRow())),
          ),
        if (!isNew) ...[
          const SizedBox(height: 24),
          ChunkyButton.secondary(
            label: 'Delete food',
            icon: Icons.delete_outline_rounded,
            onPressed: _saving ? null : _delete,
          ),
        ],
      ],
    );
  }
}
