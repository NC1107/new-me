import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/pressable.dart';

/// Dark enough to read on the canvas; the flame fill itself is too light for text.
const _kFlameText = Color(0xFFB45309);

String greetingFor(DateTime now, String name) {
  final part = now.hour < 12
      ? 'Good morning'
      : now.hour < 18
      ? 'Good afternoon'
      : 'Good evening';
  return name.trim().isEmpty ? part : '$part, ${name.trim()}';
}

/// The one row above the day: the greeting and date, the streak (opens the streak sheet), the
/// coach when the server has one, and the partner's avatar ringed by their day (opens Us).
class TodayTopBar extends StatelessWidget {
  const TodayTopBar({
    super.key,
    required this.name,
    required this.now,
    required this.localToday,
    required this.streak,
    required this.partner,
    required this.onOpenUs,
    required this.onStreak,
    this.onCoach,
  });

  final String name;
  final DateTime now;
  final String localToday;
  final int streak;
  final BoardUser? partner;
  final VoidCallback onOpenUs;
  final VoidCallback onStreak;

  /// Opens the coach chat; null hides the button, as when the server has no Claude key.
  final VoidCallback? onCoach;

  @override
  Widget build(BuildContext context) {
    final p = partner;
    final coach = onCoach;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                container: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(greetingFor(now, name), maxLines: 1, style: AppText.title),
                ),
              ),
              const SizedBox(height: 2),
              Text(dayLong(localToday), style: AppText.caption),
            ],
          ),
        ),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: _Stat(
            icon: Icons.local_fire_department_rounded,
            iconColor: kFlame,
            textColor: _kFlameText,
            value: streak.formatted,
            caption: 'Your streak',
            label: 'Your streak, $streak day streak',
            onTap: onStreak,
          ),
        ),
        if (coach != null) _CoachButton(onTap: coach),
        if (p != null)
          Semantics(
            container: true,
            button: true,
            label: '${p.name}, ${p.today.goalPercent} percent of the goal today, open Us',
            excludeSemantics: true,
            onTap: onOpenUs,
            child: Pressable(
              onTap: onOpenUs,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(child: _PartnerRing(user: p)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A round button that opens the coach chat.
class _CoachButton extends StatelessWidget {
  const _CoachButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      container: true,
      button: true,
      label: 'Ask your coach',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_rounded, size: 20, color: palette.lip),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.value,
    required this.label,
    required this.caption,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final String value;
  final String label;

  /// Names the figure, so it is never mistaken for the Together streak on Us.
  final String caption;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.tabular(
                    AppText.headline.copyWith(color: textColor, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: kInkSecondary, height: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
    return Semantics(
      container: true,
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
        painter: _RingPainter(percent: user.today.goalPercent / 100, color: palette.fill),
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
