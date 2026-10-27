import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The person's colour darkened just enough to read as small text on both the canvas and their
/// own tint. The lip alone is under 4.5:1 for Honey and borderline for Fern and Coral.
Color readableAccent(AccentPalette p) {
  for (var step = 0; step <= 10; step++) {
    final c = Color.lerp(p.lip, kInk, step / 10)!;
    if (_contrast(c, kCanvas) >= 4.5 && _contrast(c, p.tint) >= 4.5) return c;
  }
  return kInk;
}

extension AccentTextContext on BuildContext {
  /// The person's colour for small text and thin icons.
  Color get accentText => readableAccent(accentPalette);
}
