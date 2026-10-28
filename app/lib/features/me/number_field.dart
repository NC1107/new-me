import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

final _digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)];

/// A whole-number field with its label above, an optional unit inside and, when [clearable],
/// a button that empties it. Offline the field ignores touches rather than looking disabled.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = 'Not set',
    this.unit,
    this.clearable = false,
    this.editable = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? unit;
  final bool clearable;
  final bool editable;
  final VoidCallback? onChanged;

  /// The label with its unit, since the unit is drawn inside the field and not in the label.
  String get _spokenLabel => switch (unit) {
    null => label,
    'g' => '$label, grams',
    final u when label.contains(u) => label,
    final u => '$label, $u',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ExcludeSemantics(
            child: Text(label, style: AppText.caption.copyWith(color: kInkSecondary)),
          ),
        ),
        IgnorePointer(
          ignoring: !editable,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => Semantics(
              label: _spokenLabel,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: _digits,
                onChanged: (_) => onChanged?.call(),
                style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
                cursorColor: context.accent,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: AppText.body.copyWith(color: kInkMuted),
                  filled: true,
                  fillColor: kSurface,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  suffixIcon: _Suffix(
                    unit: unit,
                    onClear: clearable && value.text.isNotEmpty && editable
                        ? () {
                            HapticFeedback.selectionClick();
                            controller.clear();
                            onChanged?.call();
                          }
                        : null,
                    label: label,
                  ),
                  suffixIconConstraints: const BoxConstraints(minHeight: 48),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  constraints: const BoxConstraints(minHeight: 52),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kRadiusField),
                    borderSide: const BorderSide(color: kBorder, width: kBorderWidth),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kRadiusField),
                    borderSide: BorderSide(color: context.accent, width: kBorderWidth),
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

class _Suffix extends StatelessWidget {
  const _Suffix({required this.unit, required this.onClear, required this.label});

  final String? unit;
  final VoidCallback? onClear;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (unit != null) Text(unit!, style: AppText.label.copyWith(color: kInkSecondary)),
      if (onClear != null)
        IconButton(
          tooltip: 'Clear $label',
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onClear,
          icon: const Icon(Icons.cancel_rounded, size: 22, color: kInkMuted),
        )
      else
        const SizedBox(width: 14),
    ],
  );
}
