import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../insights/insights_logic.dart';

const _kRingSize = 104.0;

/// One person's day: avatar, a ring filled to today's percent with today's points inside, the
/// streak, and week and season points. Text follows Dynamic Type up to a limit, because the
/// card is half the screen wide.
class PersonCard extends StatelessWidget {
  const PersonCard({super.key, required this.user, required this.now, this.onCheer});

  final BoardUser user;
  final DateTime now;

  /// Set on the partner's card: tapping it opens the cheer sheet.
  final VoidCallback? onCheer;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(user.color);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kBoardColumnMaxTextScale,
      child: Builder(
        // A tappable card is its own node, or it would merge with its neighbour in the row.
        builder: (context) => Semantics(
          container: onCheer != null,
          child: AppCard(
            onTap: onCheer,
            semanticLabel: onCheer == null ? null : 'Cheer ${user.name}',
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
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
                  child: _Ring(user: user, palette: palette),
                ),
                const SizedBox(height: 6),
                Text(
                  '${user.today.percent}%${user.today.counted ? ' - counted' : ''}',
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(
                    color: user.today.counted ? kSuccessText : kInkSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 20, color: kFlame),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        user.streak < 1 ? 'No streak yet' : '${user.streak}-day streak',
                        style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Stat(label: 'Week', value: user.week),
                if (user.workoutsThisWeek case final n?) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    container: true,
                    label: '${workoutCountLabel(n)} this week',
                    excludeSemantics: true,
                    child: _Stat(label: 'Workouts', value: n),
                  ),
                ],
                const SizedBox(height: 4),
                _Stat(label: 'Season', value: user.season),
                const SizedBox(height: 10),
                Text(
                  user.syncedAt == null
                      ? 'Health not synced'
                      : 'synced ${relativeTime(user.syncedAt!, now)}',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
                if (onCheer != null) ...[const SizedBox(height: 12), _CheerHint(palette: palette)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill that says the card can be tapped to cheer.
class _CheerHint extends StatelessWidget {
  const _CheerHint({required this.palette});

  final AccentPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 36),
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
  );
}

/// Success green dark enough for 13px text on white.
const kSuccessText = Color(0xFF237A4B);

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: AppText.caption.copyWith(color: kInkSecondary)),
      ),
      Text(
        value.formatted,
        style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
      ),
    ],
  );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.user, required this.palette});

  final BoardUser user;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fraction = (user.today.percent / 100).clamp(0.0, 1.0);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Semantics(
        label: '${user.name}: ${user.today.points} points today, ${user.today.percent} percent',
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: _kRingSize,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduce ? fraction : 0, end: fraction),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) =>
                CustomPaint(painter: _RingPainter(value, palette), child: child),
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
  const _RingPainter(this.fraction, this.palette);

  final double fraction;
  final AccentPalette palette;

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
        ..color = palette.fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.palette.fill != palette.fill;
}
