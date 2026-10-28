import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/pressable.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import 'person_sheet.dart';
import '../streaks/streak_visuals.dart';

const _kRingSize = 104.0;

/// One person's day: avatar, name, a ring filled to today's percent with today's points inside,
/// the goal percent and the streak. Tapping the card opens the rest (week, workouts, season,
/// freezes, last sync). Text follows Dynamic Type up to a limit, because the card is half the
/// screen wide.
class PersonCard extends StatelessWidget {
  const PersonCard({
    super.key,
    required this.user,
    required this.now,
    this.onCheer,
    this.inviteStreak = false,
    this.isMe = false,
  });

  final BoardUser user;
  final DateTime now;

  /// Set on the partner's card: the Cheer button opens the cheer sheet.
  final VoidCallback? onCheer;

  /// Whether a zero streak says "Start a streak today". Paired, the Us header says it once.
  final bool inviteStreak;

  /// Marks my own card in a pair, so it ends with the same height as the partner's Cheer row.
  final bool isMe;

  /// What a screen reader hears for the card: the same facts the card shows.
  String get semanticLabel {
    final goal = user.away.today
        ? 'away today'
        : '${user.today.goalPercent} percent of the goal${user.today.counted ? ', counted' : ''}';
    final streak = user.streak < 1 ? 'no streak yet' : '${user.streak}-day streak';
    return '${user.name}: ${user.today.points} points today, $goal, $streak. Show details';
  }

  @override
  Widget build(BuildContext context) {
    final palette = accentById(user.color);
    final counted = user.today.counted && !user.away.today;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kBoardColumnMaxTextScale,
      child: Builder(
        builder: (context) => Semantics(
          container: true,
          child: AppCard(
            onTap: () => showPersonSheet(context, user: user, now: now),
            semanticLabel: semanticLabel,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Avatar(name: user.name, palette: palette, size: 44),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: _Ring(user: user, palette: palette, counted: counted),
                      ),
                      const SizedBox(height: 6),
                      _GoalLine(user: user, counted: counted),
                      if (user.streak >= 1 || inviteStreak) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 20,
                              color: kFlame,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                user.streak < 1
                                    ? 'Start a streak today'
                                    : '${user.streak}-day streak',
                                textAlign: TextAlign.center,
                                style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (onCheer != null) ...[
                  const SizedBox(height: 12),
                  _CheerButton(name: user.name, palette: palette, onTap: onCheer!),
                ] else if (isMe) ...[
                  const SizedBox(height: 12),
                  ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      child: const Text('You', style: AppText.caption),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The goal percent, with a check when the day counted. Away days say so instead.
class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.user, required this.counted});

  final BoardUser user;
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final color = user.away.today
        ? kFreezeText
        : counted
        ? kSuccessText
        : kInkSecondary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (counted) ...[
          Icon(Icons.check_circle_rounded, size: 16, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            user.away.today ? 'Away today' : '${user.today.goalPercent}%',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// The partner's Cheer button. It is its own button so the card behind it can open details.
class _CheerButton extends StatelessWidget {
  const _CheerButton({required this.name, required this.palette, required this.onTap});

  final String name;
  final AccentPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Cheer $name',
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration_rounded, size: 18, color: palette.lip),
            const SizedBox(width: 6),
            Text(
              'Cheer',
              style: AppText.label.copyWith(color: palette.lip, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Success green dark enough for 13px text on white.
const kSuccessText = Color(0xFF237A4B);

class _Ring extends StatelessWidget {
  const _Ring({required this.user, required this.palette, required this.counted});

  final BoardUser user;
  final AccentPalette palette;
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fraction = (user.today.goalPercent / 100).clamp(0.0, 1.0);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Semantics(
        label:
            '${user.name}: ${user.today.points} points today, ${user.today.goalPercent} percent of the goal',
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: _kRingSize,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduce ? fraction : 0, end: fraction),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => CustomPaint(
              painter: _RingPainter(value, counted ? kSuccess : palette.fill),
              child: child,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        user.today.points.formatted,
                        style: AppText.tabular(AppText.title.copyWith(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  Text('points', style: AppText.caption.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction, this.color);

  final double fraction;
  final Color color;

  static const _stroke = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(_stroke / 2);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = kSunken,
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}
