import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pressable.dart';

/// The card every screen is built from: white, 2px border, radius 16, no shadow.
/// With [onTap] it presses in like a button.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = kSurface,
    this.borderColor = kBorder,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  /// Names a tappable card for screen readers when its text alone would not.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: borderColor, width: kBorderWidth),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        onTap: onTap,
        // A full-width card moving 4% looks heavy, so cards press gentler than buttons.
        scale: 0.98,
        child: card,
      ),
    );
  }
}
