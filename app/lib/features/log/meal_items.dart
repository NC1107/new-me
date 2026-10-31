import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/pressable.dart';
import 'log_panes.dart' show gramsInputFormatter, gramsText;

const kMaxItemQuantity = 1000.0;
const kMinItemQuantity = 0.25;
const _kMaxMealKcal = 10000;

/// A [MealItem] with an identity of its own, so a row keeps its text fields when the rows
/// around it are deleted.
class MealEntry {
  MealEntry(this.item) : key = UniqueKey();

  final Key key;
  MealItem item;
}

/// "1", "0.5", "2.25": a quantity without trailing zeros.
String quantityText(double q) => q.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// How far - and + move an amount: tens for weights and volumes, halves for everything else.
double quantityStep(String unit) => switch (unit.toLowerCase()) {
  'g' || 'gram' || 'grams' || 'ml' => 10,
  _ => 0.5,
};

/// The name a one-meal log gets: the item names joined, cut to what the server accepts.
String joinedMealName(List<MealItem> items) {
  final joined = items.map((i) => i.name.trim()).where((n) => n.isNotEmpty).join(', ');
  if (joined.isEmpty) return 'Meal';
  return joined.length <= 80 ? joined : joined.substring(0, 80).trimRight();
}

({int kcal, num protein, num carbs, num fat, num fiber, int share}) mealTotals(
  List<MealItem> items,
) {
  var kcal = 0;
  var dbKcal = 0;
  double protein = 0, carbs = 0, fat = 0, fiber = 0;
  for (final i in items) {
    kcal += i.kcal;
    if (i.fromDatabase) dbKcal += i.kcal;
    protein += i.protein;
    carbs += i.carbs;
    fat += i.fat;
    fiber += i.fiber;
  }
  num tenth(double v) => (v * 10).round() / 10;
  return (
    kcal: kcal,
    protein: tenth(protein),
    carbs: tenth(carbs),
    fat: tenth(fat),
    fiber: tenth(fiber),
    share: kcal == 0 ? 0 : (100 * dbKcal / kcal).round(),
  );
}

String _g(num v) => v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);

/// The itemized result of "Describe it" or the food search: one editable row per food, the
/// total, how much of it came from a database, and the two ways to log it.
class ItemizedMeal extends StatelessWidget {
  const ItemizedMeal({
    super.key,
    required this.entries,
    required this.busy,
    required this.onChanged,
    required this.onLogOne,
    required this.onLogSeparately,
    required this.onClear,
  });

  final List<MealEntry> entries;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onLogOne;
  final VoidCallback onLogSeparately;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final items = [for (final e in entries) e.item];
    final totals = mealTotals(items);
    final tooBig = totals.kcal > _kMaxMealKcal;
    final canLog = !busy && entries.isNotEmpty && totals.kcal > 0 && !tooBig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) ...[
          _ItemRow(
            key: entry.key,
            entry: entry,
            onChanged: onChanged,
            onDelete: () {
              entries.remove(entry);
              onChanged();
            },
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSunken,
            borderRadius: BorderRadius.circular(kRadiusField),
          ),
          child: Semantics(
            container: true,
            label:
                'Total ${totals.kcal.formatted} kilocalories. ${totals.share} percent from '
                'nutrition databases.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: AppText.label.copyWith(color: kInkSecondary)),
                Text('${totals.kcal.formatted} kcal', style: AppText.title),
                Text(
                  'Protein ${_g(totals.protein)} g, carbs ${_g(totals.carbs)} g, '
                  'fat ${_g(totals.fat)} g',
                  style: AppText.label.copyWith(color: kInkSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  '${totals.share}% from nutrition databases',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                ),
                if (tooBig)
                  Text(
                    'At most ${_kMaxMealKcal.formatted} kcal in one log',
                    style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        ChunkyButton(label: 'Log as one meal', onPressed: canLog ? onLogOne : null),
        if (entries.length > 1) ...[
          const SizedBox(height: 10),
          ChunkyButton.secondary(
            label: 'Log separately',
            onPressed: canLog ? onLogSeparately : null,
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            child: GestureDetector(
              onTap: busy ? null : onClear,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  widthFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Clear and enter by hand',
                    style: AppText.label.copyWith(color: context.accentText),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({super.key, required this.entry, required this.onChanged, required this.onDelete});

  final MealEntry entry;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final _name = TextEditingController(text: widget.entry.item.name);
  late final _quantity = TextEditingController(text: quantityText(widget.entry.item.quantity));
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _fixing = false;

  MealItem get _item => widget.entry.item;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    for (final c in [_kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setQuantity(double q, {bool rewrite = true}) {
    final clamped = q.clamp(kMinItemQuantity, kMaxItemQuantity).toDouble();
    widget.entry.item = _item.withQuantity(clamped);
    if (rewrite) _quantity.text = quantityText(clamped);
    widget.onChanged();
  }

  void _toggleFix() {
    if (!_fixing) {
      _kcal.text = '${_item.kcal}';
      _protein.text = gramsText(_item.protein);
      _carbs.text = gramsText(_item.carbs);
      _fat.text = gramsText(_item.fat);
    }
    setState(() => _fixing = !_fixing);
  }

  void _typedNumbers() {
    final kcal = int.tryParse(_kcal.text);
    if (kcal == null || kcal > _kMaxMealKcal) return;
    num grams(TextEditingController c) => num.tryParse(c.text) ?? 0;
    widget.entry.item = _item.withNumbers(
      kcal: kcal,
      protein: grams(_protein).toDouble(),
      carbs: grams(_carbs).toDouble(),
      fat: grams(_fat).toDouble(),
    );
    widget.onChanged();
  }

  Widget _numberField(String label, TextEditingController c, {bool whole = false}) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, textAlign: TextAlign.center, style: AppText.caption),
        const SizedBox(height: 4),
        Semantics(
          label: '$label of ${_item.name}',
          child: TextField(
            controller: c,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: !whole),
            inputFormatters: whole
                ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)]
                : [gramsInputFormatter],
            style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
            cursorColor: context.accent,
            onChanged: (_) => _typedNumbers(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: kSunken,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusField),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _typedQuantity(String text) {
    final q = double.tryParse(text);
    if (q != null && q >= kMinItemQuantity && q <= kMaxItemQuantity) {
      _setQuantity(q, rewrite: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final step = quantityStep(item.unit);
    final person = context.accentPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusField),
        border: Border.all(color: kBorder, width: kBorderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Name of ${item.text}',
                  child: TextField(
                    controller: _name,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    cursorColor: context.accent,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(80)],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) {
                      widget.entry.item = _item.withName(v);
                      widget.onChanged();
                    },
                  ),
                ),
              ),
              _IconTap(
                icon: Icons.close_rounded,
                label: 'Remove ${item.name}',
                onTap: widget.onDelete,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChunkyIconButton(
                  icon: Icons.remove_rounded,
                  semanticLabel: 'Less ${item.name}',
                  size: 44,
                  kind: ChunkyKind.secondary,
                  onPressed: item.quantity - step >= kMinItemQuantity
                      ? () => _setQuantity(item.quantity - step)
                      : null,
                ),
                SizedBox(
                  width: 64,
                  child: Semantics(
                    label: 'Amount of ${item.name}',
                    child: TextField(
                      controller: _quantity,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}\.?\d{0,2}')),
                      ],
                      style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
                      cursorColor: context.accent,
                      onChanged: _typedQuantity,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: kSunken,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kRadiusField),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                ChunkyIconButton(
                  icon: Icons.add_rounded,
                  semanticLabel: 'More ${item.name}',
                  size: 44,
                  onPressed: item.quantity + step <= kMaxItemQuantity
                      ? () => _setQuantity(item.quantity + step)
                      : null,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    item.unit,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: kInkSecondary),
                  ),
                ),
                _SourceChip(item: item, palette: person),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Text(
              '${item.kcal.formatted} kcal   protein ${_g(item.protein)} g   '
              'carbs ${_g(item.carbs)} g   fat ${_g(item.fat)} g',
              style: AppText.label.copyWith(color: kInkSecondary),
            ),
          ),
          if (_fixing)
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 8),
              child: Row(
                children: [
                  _numberField('kcal', _kcal, whole: true),
                  const SizedBox(width: 6),
                  _numberField('Protein g', _protein),
                  const SizedBox(width: 6),
                  _numberField('Carbs g', _carbs),
                  const SizedBox(width: 6),
                  _numberField('Fat g', _fat),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: _fixing ? 'Done fixing ${item.name}' : 'Fix the numbers of ${item.name}',
              excludeSemantics: true,
              onTap: _toggleFix,
              child: Pressable(
                onTap: _toggleFix,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _fixing ? Icons.check_rounded : Icons.tune_rounded,
                        size: 20,
                        color: context.accentText,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _fixing ? 'Done' : 'Fix the numbers',
                          style: AppText.label.copyWith(color: context.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (item.source == FoodSource.estimated)
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                toggled: item.saveToLibrary,
                label: 'Keep ${item.name} in My foods',
                excludeSemantics: true,
                onTap: () => _toggleSave(),
                child: Pressable(
                  onTap: _toggleSave,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.saveToLibrary
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 20,
                          color: context.accentText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.saveToLibrary ? 'Will keep in My foods' : 'Keep in My foods',
                            style: AppText.label.copyWith(color: context.accentText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSave() {
    widget.entry.item = _item.withSave(!_item.saveToLibrary);
    widget.onChanged();
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22, color: kInkSecondary)),
    ),
  );
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.item, required this.palette});

  final MealItem item;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) {
    final estimated = item.source == FoodSource.estimated;
    return Semantics(
      label: 'Source: ${item.source.chip}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: estimated ? kSurface : palette.tint,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: estimated ? kBorder : palette.fill, width: 1.5),
        ),
        child: Text(
          item.source.chip,
          style: AppText.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: estimated ? kInkSecondary : kInk,
          ),
        ),
      ),
    );
  }
}
