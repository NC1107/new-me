import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/pressable.dart';

/// A tappable pill for quick values, portions and recent meals. Selected, it washes in the
/// person's tint with a 2px border in their colour.
class LogChip extends StatelessWidget {
  const LogChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.semanticLabel,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;

  /// Drops the horizontal padding and minimum width so several chips share one row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Pressable(
        haptic: false,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : kMotionDuration,
          constraints: BoxConstraints(minHeight: 44, minWidth: compact ? 0 : 56),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? person.tint : kSurface,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: selected ? person.fill : kBorder, width: kBorderWidth),
          ),
          // Centering through a widthFactor keeps the chip as wide as its label inside a Wrap.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: !enabled
                    ? kInkMuted
                    : selected
                    ? context.accentText
                    : kInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
