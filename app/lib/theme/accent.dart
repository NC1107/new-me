import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// A person's colour: [fill] for buttons and bars, [lip] for the 3D button edge and text on
/// white, [tint] for selected states and icon circles.
///
/// Carried on the app's [ThemeData] as a [ThemeExtension] so any widget can read the current
/// person's colour via `context.accentPalette` without plumbing a provider everywhere.
@immutable
class AccentPalette extends ThemeExtension<AccentPalette> {
  const AccentPalette({
    required this.id,
    required this.name,
    required this.fill,
    required this.lip,
    required this.tint,
    required this.onFill,
  });

  /// Derives the text colour: white where it holds 3:1 (large bold text), ink where it does not.
  factory AccentPalette.of(String id, String name, int fill, int lip, int tint) {
    final f = Color(fill);
    return AccentPalette(
      id: id,
      name: name,
      fill: f,
      lip: Color(lip),
      tint: Color(tint),
      onFill: _contrast(Colors.white, f) >= 3.0 ? Colors.white : kInk,
    );
  }

  /// The stored colour key, as the server knows it.
  final String id;
  final String name;
  final Color fill;
  final Color lip;
  final Color tint;

  /// Text and icons on top of [fill].
  final Color onFill;

  Color get base => fill;
  Color get hover => lip;
  Color get light => tint;
  Color get onAccent => onFill;

  @override
  AccentPalette copyWith({Color? fill, Color? lip, Color? tint, Color? onFill}) => AccentPalette(
    id: id,
    name: name,
    fill: fill ?? this.fill,
    lip: lip ?? this.lip,
    tint: tint ?? this.tint,
    onFill: onFill ?? this.onFill,
  );

  @override
  AccentPalette lerp(ThemeExtension<AccentPalette>? other, double t) {
    if (other is! AccentPalette) return this;
    return AccentPalette(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      fill: Color.lerp(fill, other.fill, t)!,
      lip: Color.lerp(lip, other.lip, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      onFill: Color.lerp(onFill, other.onFill, t)!,
    );
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Tweens between two person colours, so a recolour glides instead of snapping.
class AccentTween extends Tween<AccentPalette> {
  AccentTween({super.begin, super.end});

  @override
  AccentPalette lerp(double t) => begin!.lerp(end, t);
}

/// The six person colours; the stored keys are the ones the server accepts. Green is first.
final List<AccentPalette> kAccentPresets = [
  AccentPalette.of('green', 'Fern', 0xFF3FA66B, 0xFF2F8553, 0xFFE6F4EC),
  AccentPalette.of('sky', 'Sky', 0xFF3D8FD6, 0xFF2C70AD, 0xFFE5F0FA),
  AccentPalette.of('violet', 'Iris', 0xFF7B6CD9, 0xFF5F51B5, 0xFFEEEBFA),
  AccentPalette.of('amber', 'Honey', 0xFFE89A2C, 0xFFBF7A17, 0xFFFCF1E1),
  AccentPalette.of('rose', 'Coral', 0xFFE5675A, 0xFFBF4C40, 0xFFFCE9E7),
  AccentPalette.of('teal', 'Lagoon', 0xFF2A9D8F, 0xFF1F7A6F, 0xFFE3F3F1),
];

/// Look up a preset by id, falling back to the default green.
AccentPalette accentById(String? id) =>
    kAccentPresets.firstWhere((p) => p.id == id, orElse: () => kAccentPresets.first);

/// `context.accent` and friends - resolve the live person colour from the theme.
extension AccentContext on BuildContext {
  AccentPalette get accentPalette =>
      Theme.of(this).extension<AccentPalette>() ?? kAccentPresets.first;
  Color get accent => accentPalette.fill;
  Color get accentLip => accentPalette.lip;
  Color get accentTint => accentPalette.tint;
  Color get accentHover => accentPalette.lip;
  Color get accentLight => accentPalette.tint;
  Color get onAccent => accentPalette.onFill;
}

/// The light theme for [accent]; each person gets their own colour.
ThemeData themeFor(AccentPalette accent) {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    fontFamily: kFontFamily,
    colorScheme: ColorScheme.light(
      primary: accent.fill,
      onPrimary: accent.onFill,
      secondary: accent.lip,
      surface: kSurface,
      onSurface: kInk,
      outline: kBorder,
      error: kDanger,
    ),
  );
  return base.copyWith(
    textTheme: buildTextTheme(),
    primaryTextTheme: buildTextTheme(),
    scaffoldBackgroundColor: kCanvas,
    canvasColor: kCanvas,
    cardColor: kSurface,
    dividerColor: kBorder,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent.fill,
      selectionColor: accent.fill.withValues(alpha: 0.25),
      selectionHandleColor: accent.fill,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: kBorder, width: kBorderWidth),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard + 4),
        side: const BorderSide(color: kBorder, width: kBorderWidth),
      ),
      titleTextStyle: AppText.headline,
      contentTextStyle: AppText.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: AppText.label.copyWith(color: Colors.white),
      actionTextColor: accent.tint,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusField)),
    ),
    extensions: [accent],
  );
}
