import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/chunky_button.dart';
import '../log/big_number_stepper.dart';
import '../log/log_chip.dart';
import '../me/number_field.dart';
import '../../util/units.dart';
import '../../widgets/units_scope.dart';
import 'set_assist.dart';

/// What one logged set holds before it is sent.
typedef SetValues = ({int amount, double? loadKg, int? rir});

/// Server limits for one set (server/internal/api/exercises.go).
const kMaxSetReps = 500;
const kMaxSetSeconds = 3600;
const kMaxLoadKg = 500.0;

/// Reps in reserve offered as chips, 0 to 4 (Zourdos et al. 2016).
const kRirChoices = [0, 1, 2, 3, 4];

enum _Assist { none, counting, timing }

/// Logs one set: reps or seconds on a big stepper, the load for loaded work, and reps in reserve.
/// Starts from a target so the common case is one tap.
class SetForm extends StatefulWidget {
  const SetForm({
    super.key,
    required this.timed,
    required this.loaded,
    required this.onLog,
    this.initialAmount,
    this.initialLoadKg,
    this.initialRir,
    this.buttonLabel = 'Log set',
  });

  final bool timed;
  final bool loaded;
  final int? initialAmount;
  final double? initialLoadKg;
  final int? initialRir;
  final String buttonLabel;

  /// Sends the set; a thrown error keeps the form as it was.
  final Future<void> Function(SetValues values) onLog;

  @override
  State<SetForm> createState() => _SetFormState();
}

class _SetFormState extends State<SetForm> {
  late final _amount = TextEditingController(text: _initialAmount);
  late final _load = TextEditingController(text: _initialLoad);
  late int? _rir = widget.initialRir;
  bool _busy = false;
  _Assist _assist = _Assist.none;

  // The units are read once: a set form lives inside one sheet.
  late final Units _units = context.units;

  String get _initialLoad {
    final kg = widget.initialLoadKg;
    if (kg == null) return '';
    final v = _units.isImperial ? (_units.weightIn(kg) * 2).round() / 2 : (kg * 10).round() / 10;
    return v.formatted;
  }

  double get _maxLoad => _units.weightIn(kMaxLoadKg).floorToDouble();

  String get _initialAmount {
    final a = widget.initialAmount;
    return a == null || a <= 0 ? '' : '$a';
  }

  int get _max => widget.timed ? kMaxSetSeconds : kMaxSetReps;
  int? get _amountValue => int.tryParse(_amount.text);
  double? get _loadValue => double.tryParse(_load.text.replaceAll(',', '.'));

  String? get _amountError {
    final a = _amountValue;
    if (a != null && a > _max) return 'At most $_max ${widget.timed ? 'seconds' : 'reps'}';
    return null;
  }

  String? get _loadError {
    if (!widget.loaded || _load.text.trim().isEmpty) return null;
    final l = _loadValue;
    if (l == null || l <= 0 || l > _maxLoad) {
      return 'Load must be above 0 and at most ${_maxLoad.formatted} ${_units.weightUnit}';
    }
    return null;
  }

  bool get _valid => (_amountValue ?? 0) > 0 && _amountError == null && _loadError == null;

  void _fill(int amount) {
    setState(() {
      _amount.text = '${amount.clamp(1, _max)}';
      _assist = _Assist.none;
    });
  }

  void _step(int by) {
    final next = ((_amountValue ?? 0) + by).clamp(0, _max);
    setState(() => _amount.text = '$next');
  }

  @override
  void dispose() {
    _amount.dispose();
    _load.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onLog((
        amount: _amountValue!,
        loadKg: widget.loaded && _load.text.trim().isNotEmpty
            ? (_units.weightToKg(_loadValue!) * 100).round() / 100
            : null,
        rir: widget.timed ? null : _rir,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.timed ? 5 : 1;
    final amount = _amountValue ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigNumberStepper(
          controller: _amount,
          unitLabel: widget.timed ? 'seconds' : 'reps',
          onMinus: amount > 0 ? () => _step(-step) : null,
          onPlus: amount < _max ? () => _step(step) : null,
          onChanged: (_) => setState(() {}),
          errorText: _amountError,
        ),
        const SizedBox(height: 12),
        switch (_assist) {
          _Assist.counting => RepCounter(
            max: _max,
            onDone: _fill,
            onCancel: () => setState(() => _assist = _Assist.none),
          ),
          _Assist.timing => HoldTimer(
            seconds: amount,
            onDone: _fill,
            onCancel: () => setState(() => _assist = _Assist.none),
          ),
          _Assist.none => ChunkyButton.secondary(
            label: widget.timed ? 'Start timer' : 'Count reps',
            icon: widget.timed ? Icons.timer_outlined : Icons.touch_app_outlined,
            onPressed: widget.timed
                ? (amount > 0 ? () => setState(() => _assist = _Assist.timing) : null)
                : () => setState(() => _assist = _Assist.counting),
          ),
        },
        if (widget.loaded) ...[
          const SizedBox(height: 16),
          NumberField(
            controller: _load,
            label: 'Load',
            hint: 'Bodyweight',
            unit: _units.weightUnit,
            onChanged: () => setState(() {}),
          ),
          if (_loadError case final error?) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: AppText.caption.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
        ],
        if (!widget.timed) ...[
          const SizedBox(height: 16),
          Text('Reps in reserve', style: AppText.caption.copyWith(color: kInkSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final r in kRirChoices) ...[
                if (r > 0) const SizedBox(width: 8),
                Expanded(
                  child: LogChip(
                    label: r == 4 ? '4+' : '$r',
                    compact: true,
                    selected: _rir == r,
                    semanticLabel: '$r reps in reserve',
                    onTap: () => setState(() => _rir = _rir == r ? null : r),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'How many more reps you could have done with good form.',
            style: AppText.caption.copyWith(color: kInkMuted),
          ),
        ],
        const SizedBox(height: 20),
        ChunkyButton(
          label: widget.buttonLabel,
          busy: _busy,
          onPressed: _valid && _assist == _Assist.none ? _submit : null,
        ),
      ],
    );
  }
}
