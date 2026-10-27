import 'package:flutter/material.dart';

/// Colour, spacing and shape tokens for the light New Me theme (docs/design-v2.md).
/// Person colours live in accent.dart and quest category colours in quest_colors.dart.

const kCanvas = Color(0xFFFBF8F3);
const kSurface = Color(0xFFFFFFFF);
const kSunken = Color(0xFFF3EFE8);
const kBorder = Color(0xFFE8E2D8);
const kLip = Color(0xFFD9D2C5);

const kInk = Color(0xFF25283D);
const kInkSecondary = Color(0xFF4B4F63);

/// Clears 4.5:1 on the canvas, which is the dimmest background it sits on.
const kInkMuted = Color(0xFF6E7283);

const kFlame = Color(0xFFF08A24);
const kDanger = Color(0xFFD9534F);

/// Error text on white or canvas; the plain danger red is under 4.5:1 for small text.
const kDangerText = Color(0xFFB23C38);
const kSuccess = Color(0xFF3FA66B);

/// Names the first screens were written against; they resolve to the light tokens.
const kBgMain = kCanvas;
const kBgSurface = kSurface;
const kBgSurfaceHover = kSunken;
const kFgPrimary = kInk;
const kFgSecondary = kInkSecondary;
const kFgMuted = kInkMuted;

const kGutter = 20.0;
const kCardGap = 12.0;
const kContentMaxWidth = 480.0;

const kRadiusCard = 16.0;
const kRadiusButton = 14.0;
const kRadiusField = 12.0;
const kBorderWidth = 2.0;

const kBottomNavIconSize = 23.0;
const kBottomNavIconLabelGap = 3.0;
const kBottomNavLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);

/// The bottom bar has a fixed height, so its labels follow Dynamic Type only up to this factor.
const kBottomNavMaxTextScale = 1.2;

/// The Board columns hold a 7-day strip that cannot grow with the largest text sizes.
const kBoardColumnMaxTextScale = 1.5;

const kTapScale = 0.96;
const kTapDuration = Duration(milliseconds: 90);
const kPopDuration = Duration(milliseconds: 250);
const kPageDuration = Duration(milliseconds: 300);
const kMotionDuration = Duration(milliseconds: 200);
