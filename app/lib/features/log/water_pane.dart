import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import 'big_number_stepper.dart';
import 'log_chip.dart';
import 'log_panes.dart';

/// The most water one entry may hold, matching the server.
const kMaxWaterMl = 5000;

/// Above this one entry asks before it is saved.
const kConfirmWaterMl = 2000;

/// The quick-add amounts and the typed amount's step, in the person's unit.
class WaterAmounts {
  const WaterAmounts({required this.chips, required this.step});

  final List<int> chips;
  final int step;

  static WaterAmounts of(Units units) => units.isImperial
      ? const WaterAmounts(chips: [8, 16], step: 1)
      : const WaterAmounts(chips: [250, 500], step: 50);
}

/// Log water: the chips add a glass-sized amount to the number, which can also be typed or
/// stepped, and Save logs the total. Amounts are shown in the person's unit and always stored in
/// millilitres.
class WaterPane extends StatefulWidget {
  const WaterPane({
    super.key,
    required this.units,
    required this.busy,
    required this.failed,
    required this.onLog,
    this.drankMl,
    this.goalMl,
  });

  /// Today's water so far and the goal, in millilitres, when Today is loaded.
  final num? drankMl;
  final num? goalMl;

  final Units units;
  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<WaterPane> createState() => _WaterPaneState();
}

class _WaterPaneState extends State<WaterPane> {
  late final _amounts = WaterAmounts.of(widget.units);
  late final _field = TextEditingController(text: '0');

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

  void _add(int amount) => _set((_quantity ?? 0) + amount);

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
        if (widget.drankMl case final drank?) ...[
          _TodaySoFar(units: widget.units, drankMl: drank, goalMl: widget.goalMl),
          const SizedBox(height: 20),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in _amounts.chips)
              LogChip(
                label: '+$v $_unitWord',
                semanticLabel: 'Add $v $_unitWord to the amount',
                enabled: !widget.busy && q < _cap,
                onTap: () => _add(v),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Tap to add, or type the amount',
          textAlign: TextAlign.center,
          style: AppText.caption,
        ),
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

class _TodaySoFar extends StatelessWidget {
  const _TodaySoFar({required this.units, required this.drankMl, this.goalMl});

  final Units units;
  final num drankMl;
  final num? goalMl;

  @override
  Widget build(BuildContext context) {
    final goal = goalMl;
    final text = goal == null || goal <= 0
        ? 'Today so far: ${units.volume(drankMl)}'
        : 'Today so far: ${units.volumeNumber(drankMl)} of ${units.volume(goal)}';
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppText.label.copyWith(color: kInkSecondary),
    );
  }
}
