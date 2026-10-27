import 'package:flutter/material.dart';

/// Central color tokens for the New Me dark theme ("Onyx": near-black canvas, grey cards).
/// The accent is not here: it is per user, see accent.dart.

const kBgMain = Color(0xFF0A0A0A);
const kBgSurface = Color(0xFF161616);
const kBgSurfaceHover = Color(0xFF1F1F1F);
const kBorder = Color(0xFF2A2A2A);

// kFgMuted is lifted to clear WCAG AA (~5.4:1) on the surface cards.
const kFgPrimary = Color(0xFFF4F4F5);
const kFgSecondary = Color(0xFFA1A1AA);
const kFgMuted = Color(0xFF8B8B93);

const kDanger = Color(0xFFF2557B);
const kSuccess = Color(0xFF37E07E);

const kBottomNavIconSize = 23.0;
const kBottomNavIconLabelGap = 3.0;
const kBottomNavLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

/// The bottom bar has a fixed height, so its labels follow Dynamic Type only up to this factor.
const kBottomNavMaxTextScale = 1.2;

/// The Board columns hold a 7-day strip that cannot grow with the largest text sizes.
const kBoardColumnMaxTextScale = 1.5;
