import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/typography.dart';

/// A person's initial on a disc in their colour.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.palette, this.size = 48});

  final String name;
  final AccentPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.fill,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: palette.lip, offset: Offset(0, size * 0.06))],
        ),
        child: Text(
          initial,
          style: AppText.headline.copyWith(
            color: palette.onFill,
            fontSize: size * 0.46,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}
