import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/pressable.dart';
import '../streaks/streak_visuals.dart';

/// Dark enough to read on the canvas; the flame fill itself is too light for text.
const _kFlameText = Color(0xFFB45309);
const _kGemFill = Color(0xFF3D8FD6);
const _kGemText = Color(0xFF2C70AD);

/// Own avatar (opens Me), flame and streak, gem and today's points, and the partner's avatar
/// ringed by their day percent (opens Us).
class TodayTopBar extends StatelessWidget {
  const TodayTopBar({
    super.key,
    required this.name,
    required this.palette,
    required this.streak,
    required this.points,
    required this.partner,
    required this.onOpenMe,
    required this.onOpenUs,
    required this.onStreak,
    this.freezes = 0,
  });

  final String name;
  final AccentPalette palette;
  final int streak;
  final int points;
  final BoardUser? partner;
  final VoidCallback onOpenMe;
  final VoidCallback onOpenUs;
  final VoidCallback onStreak;

  /// Streak freezes held, drawn as snowflakes beside the streak.
  final int freezes;

  @override
  Widget build(BuildContext context) {
    final p = partner;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '$name, open Me',
              excludeSemantics: true,
              onTap: onOpenMe,
              child: Pressable(
                onTap: onOpenMe,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Avatar(name: name, palette: palette, size: 40),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: _Stat(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: kFlame,
                      textColor: _kFlameText,
                      value: streak.formatted,
                      label: '$streak day streak',
                      onTap: onStreak,
                    ),
                  ),
                  _Flakes(held: freezes, onTap: onStreak),
                  const SizedBox(width: 6),
                  Flexible(
                    child: _Stat(
                      icon: Icons.diamond_rounded,
                      iconColor: _kGemFill,
                      textColor: _kGemText,
                      value: points.formatted,
                      label: '$points points today',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 48,
              child: p == null
                  ? null
                  : Semantics(
                      button: true,
                      label: '${p.name}, ${p.today.percent} percent today, open Us',
                      excludeSemantics: true,
                      onTap: onOpenUs,
                      child: Pressable(
                        onTap: onOpenUs,
                        child: Center(child: _PartnerRing(user: p)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Flakes extends StatelessWidget {
  const _Flakes({required this.held, required this.onTap});

  final int held;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: freezesLabel(held),
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(child: FreezeFlakes(held: held)),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: iconColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.tabular(
                AppText.headline.copyWith(color: textColor, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null ? content : Pressable(onTap: onTap, child: content),
    );
  }
}

class _PartnerRing extends StatelessWidget {
  const _PartnerRing({required this.user});

  final BoardUser user;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(user.color);
    return SizedBox(
      width: 42,
      height: 42,
      child: CustomPaint(
        painter: _RingPainter(percent: user.today.percent / 100, color: palette.fill),
        child: Center(
          child: Avatar(name: user.name, palette: palette, size: 28),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = kSunken
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final sweep = math.pi * 2 * percent.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.percent != percent || old.color != color;
}
