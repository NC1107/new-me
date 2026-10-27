import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/chunky_icon_button.dart';

/// A big editable number with a - and a + on either side. The number is also a text field, so a
/// value far from the start can be typed instead of tapped in.
class BigNumberStepper extends StatelessWidget {
  const BigNumberStepper({
    super.key,
    required this.controller,
    required this.unitLabel,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;

  /// "push-ups", "minutes": what the number counts.
  final String unitLabel;

  /// Null disables the button, at the ends of the range.
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ChunkyIconButton(
              icon: Icons.remove_rounded,
              semanticLabel: 'Less',
              size: 56,
              kind: ChunkyKind.secondary,
              onPressed: onMinus,
            ),
            Expanded(
              // The number is already huge, so it does not grow again with Dynamic Type.
              child: MediaQuery.withNoTextScaling(
                child: Semantics(
                  label: 'Amount in $unitLabel',
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    onChanged: onChanged,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    cursorColor: context.accent,
                    style: AppText.tabular(
                      AppText.display.copyWith(
                        fontSize: 56,
                        height: 1.1,
                        color: hasError ? kDangerText : kInk,
                      ),
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: AppText.display.copyWith(
                        fontSize: 56,
                        color: kBorder,
                        height: 1.1,
                      ),
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            ChunkyIconButton(
              icon: Icons.add_rounded,
              semanticLabel: 'More',
              size: 56,
              onPressed: onPlus,
            ),
          ],
        ),
        Text(
          unitLabel,
          textAlign: TextAlign.center,
          style: AppText.label.copyWith(color: kInkMuted),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: kDangerText),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  errorText!,
                  style: AppText.caption.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
