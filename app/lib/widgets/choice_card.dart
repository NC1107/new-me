import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A selectable card: an icon circle, a title and an optional subtitle. Selected, it washes in
/// the person's tint and takes a 2px border in their colour.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.leading,
    this.selected = false,
    this.showCheck = false,
    this.iconPalette,
    this.palette,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Replaces the icon circle, for an avatar for instance.
  final Widget? leading;
  final bool selected;

  /// Shows a check circle on the right, for multi-select lists.
  final bool showCheck;

  /// Colours the icon circle (a quest's category colour); the person's colour when null.
  final AccentPalette? iconPalette;

  /// The selection colour; the person's colour from the theme when null.
  final AccentPalette? palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final person = palette ?? context.accentPalette;
    final iconColors = iconPalette ?? person;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final lead =
        leading ??
        (icon == null
            ? null
            : AnimatedContainer(
                duration: reduce ? Duration.zero : kMotionDuration,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected && iconPalette != null
                      ? kSurface
                      : (selected || iconPalette != null ? iconColors.tint : kSunken),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: selected || iconPalette != null ? iconColors.lip : kInkSecondary,
                ),
              ));

    return Semantics(
      button: true,
      selected: selected,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : kMotionDuration,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? person.tint : kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: selected ? person.fill : kBorder, width: kBorderWidth),
          ),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppText.headline.copyWith(fontSize: 17)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppText.body.copyWith(fontSize: 14, color: kInkSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (showCheck) ...[const SizedBox(width: 12), _CheckDot(on: selected, color: person)],
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.on, required this.color});

  final bool on;
  final AccentPalette color;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduce ? Duration.zero : kMotionDuration,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: on ? color.fill : kSurface,
        shape: BoxShape.circle,
        border: Border.all(color: on ? color.fill : kBorder, width: kBorderWidth),
      ),
      child: on ? Icon(Icons.check_rounded, size: 18, color: color.onFill) : null,
    );
  }
}
