import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../util/format.dart';
import '../util/units.dart';
import 'app_widgets.dart';

/// Heights the server accepts, in cm.
const kMinHeightCm = 100.0;
const kMaxHeightCm = 250.0;

/// A height typed the way the person reads it: centimetres, or feet and inches side by side.
/// Reports centimetres, or null while it is empty or out of range.
class HeightInput extends StatefulWidget {
  const HeightInput({
    super.key,
    required this.units,
    required this.initialCm,
    required this.onChanged,
    this.enabled = true,
  });

  final Units units;
  final double? initialCm;

  /// The height in cm, or null for an empty or impossible entry; [valid] says which.
  final void Function(double? cm, {required bool valid}) onChanged;
  final bool enabled;

  @override
  State<HeightInput> createState() => _HeightInputState();
}

class _HeightInputState extends State<HeightInput> {
  final _cm = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill(widget.initialCm);
  }

  @override
  void didUpdateWidget(HeightInput old) {
    super.didUpdateWidget(old);
    if (old.units != widget.units || old.initialCm != widget.initialCm) _fill(widget.initialCm);
  }

  void _fill(double? cm) {
    if (cm == null) {
      _cm.text = _feet.text = _inches.text = '';
      return;
    }
    _cm.text = ((cm * 10).round() / 10).formatted;
    final (feet, inches) = feetInches(cm);
    _feet.text = '$feet';
    _inches.text = '$inches';
  }

  @override
  void dispose() {
    _cm.dispose();
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  bool get _blank => widget.units.isImperial
      ? _feet.text.trim().isEmpty && _inches.text.trim().isEmpty
      : _cm.text.trim().isEmpty;

  double? get _value {
    if (widget.units.isImperial) {
      final feet = int.tryParse(_feet.text.trim());
      final inches = double.tryParse(_inches.text.trim().isEmpty ? '0' : _inches.text.trim());
      if (feet == null || inches == null || inches >= 12) return null;
      return cmFromFeetInches(feet, inches);
    }
    return double.tryParse(_cm.text.trim().replaceAll(',', '.'));
  }

  bool get _valid {
    if (_blank) return true;
    final v = _value;
    return v != null && v >= kMinHeightCm && v <= kMaxHeightCm;
  }

  String get _error =>
      widget.units.isImperial ? 'Between 3 ft 4 in and 8 ft 2 in' : 'Between 100 and 250 cm';

  void _changed() {
    setState(() {});
    widget.onChanged(_blank || !_valid ? null : _value, valid: _valid);
  }

  @override
  Widget build(BuildContext context) {
    final error = _valid ? null : _error;
    if (!widget.units.isImperial) {
      return IgnorePointer(
        ignoring: !widget.enabled,
        child: AppTextField(
          controller: _cm,
          hint: 'For example 178',
          semanticLabel: 'Height in centimetres',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: error,
          onChanged: (_) => _changed(),
          inputFormatters: [LengthLimitingTextInputFormatter(5)],
        ),
      );
    }
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _feet,
                  hint: 'ft',
                  semanticLabel: 'Height, feet',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _changed(),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(1),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _inches,
                  hint: 'in',
                  semanticLabel: 'Height, inches',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _changed(),
                  inputFormatters: [LengthLimitingTextInputFormatter(4)],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: AppText.caption.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
