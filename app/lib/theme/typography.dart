import 'package:flutter/material.dart';

import 'tokens.dart';

const kFontFamily = 'Nunito';

/// The v2 type scale. Colours are ink by default; copyWith for anything else.
abstract final class AppText {
  static const display = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w900,
    height: 1.15,
    color: kInk,
  );
  static const title = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: kInk,
  );
  static const headline = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: kInk,
  );
  static const body = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: kInk,
  );
  static const label = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: kInk,
  );
  static const caption = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: kInkMuted,
  );
  static const button = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    height: 1.2,
    color: kInk,
  );

  /// Fixed-width digits so a changing number does not jitter its neighbours.
  static TextStyle tabular(TextStyle style) =>
      style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

TextTheme buildTextTheme() => const TextTheme(
  displayLarge: AppText.display,
  displayMedium: AppText.display,
  displaySmall: AppText.title,
  headlineLarge: AppText.title,
  headlineMedium: AppText.title,
  headlineSmall: AppText.headline,
  titleLarge: AppText.headline,
  titleMedium: AppText.body,
  titleSmall: AppText.label,
  bodyLarge: AppText.body,
  bodyMedium: AppText.body,
  bodySmall: AppText.caption,
  labelLarge: AppText.label,
  labelMedium: AppText.label,
  labelSmall: AppText.caption,
);
