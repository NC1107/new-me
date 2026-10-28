import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import 'big_number_stepper.dart';
import 'log_chip.dart';
import 'log_panes.dart';

/// The most water one entry may hold, matching the server.
const kMaxWaterMl = 5000;

/// Above this one entry asks before it is saved.
const kConfirmWaterMl = 2000;

/// The quick-add amounts and the typed amount's start and step, in the person's unit.
class WaterAmounts {
  const WaterAmounts({required this.chips, required this.start, required this.step});

  final List<int> chips;
  final int start;
  final int step;

  static WaterAmounts of(Units units) => units.isImperial
      ? const WaterAmounts(chips: [8, 16], start: 8, step: 1)
      : const WaterAmounts(chips: [250, 500], start: 250, step: 50);
}

/// Log water: tap a glass-sized chip to add it at once, or type an amount. Amounts are shown in
/// the person's unit and always stored in millilitres.
class WaterPane extends StatefulWidget {
  const WaterPane({
    super.key,
    required this.units,
    required this.busy,
    required this.failed,
    required this.onLog,
  });

  final Units units;
  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<WaterPane> createState() => _WaterPaneState();
}

class _WaterPaneState extends State<WaterPane> {
  late final _amounts = WaterAmounts.of(widget.units);
  late final _field = TextEditingController(text: '${_amounts.start}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _unitWord => widget.units.isImperial ? 'fl oz' : 'ml';

  int get _cap => widget.units.isImperial ? (kMaxWaterMl / kMlPerFlOz).floor() : kMaxWaterMl;

  int? get _quantity => int.tryParse(_field.text);

  String? get _fieldError {
    final q = _quantity;
    return q != null && q > _cap ? 'At most $_cap $_unitWord' : null;
  }

  bool get _valid => (_quantity ?? 0) > 0 && _fieldError == null;

  void _set(int value) => setState(() => _field.text = '${value.clamp(0, _cap)}');

  void _log(int amount) {
    final ml = widget.units.mlFromDrink(amount);
    widget.onLog(
      (id, date) =>
          ActivityDraft(clientOpId: id, type: 'water', quantity: ml, unit: 'ml', date: date),
      added: 'Added $amount $_unitWord of water',
      confirm: ml > kConfirmWaterMl
          ? 'That is ${widget.units.volume(ml)} in one go. Log it?'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quantity ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in _amounts.chips)
              LogChip(
                label: '$v $_unitWord',
                semanticLabel: 'Add $v $_unitWord of water',
                enabled: !widget.busy,
                onTap: () => _log(v),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Or enter an amount', textAlign: TextAlign.center, style: AppText.caption),
        const SizedBox(height: 12),
        BigNumberStepper(
          controller: _field,
          unitLabel: _unitWord,
          errorText: _fieldError,
          onChanged: (_) => setState(() {}),
          onMinus: q > 0 && !widget.busy ? () => _set(q - _amounts.step) : null,
          onPlus: q < _cap && !widget.busy ? () => _set(q + _amounts.step) : null,
        ),
        const SizedBox(height: 24),
        ChunkyButton(
          label: widget.failed ? 'Try again' : 'Save',
          busy: widget.busy,
          onPressed: _valid && !widget.busy ? () => _log(_quantity!) : null,
        ),
      ],
    );
  }
}
