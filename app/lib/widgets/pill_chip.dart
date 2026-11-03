import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A tappable choice in a person's colour, 44pt tall, for picking one of a few values in a sheet.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AccentPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      scale: 0.97,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? palette.tint : kSurface,
          borderRadius: BorderRadius.circular(kRadiusButton),
          border: Border.all(color: selected ? palette.fill : kBorder, width: kBorderWidth),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: AppText.tabular(
              AppText.label.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? palette.lip : kInk,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
