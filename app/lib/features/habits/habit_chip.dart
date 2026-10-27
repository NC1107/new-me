import 'package:flutter/material.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/pressable.dart';
import 'habit_icons.dart';
import 'habit_items.dart';

const _kOverdueFill = Color(0xFFFFF3E0);
const _kOverdueDisc = Color(0xFFFFE0B2);
const _kOverdueInk = Color(0xFF8A4B00);

const kChipDisc = 36.0;

/// A round tappable chip: the habit icon (a check once done), its name and a caption with the
/// slot and time. Done is tinted in the person's colour, overdue is amber, the rest are white.
class HabitChip extends StatelessWidget {
  const HabitChip({super.key, required this.item, required this.onTap, this.onLongPress});

  final StripItem item;
  final VoidCallback onTap;

  /// Only count habits set a number this way.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final done = item.done;
    final overdue = item.overdue;
    final Color fill = done ? palette.tint : (overdue ? _kOverdueFill : kSurface);
    final Color border = done ? palette.fill : (overdue ? kFlame : kBorder);
    final caption = item.caption;

    final chip = AnimatedContainer(
      duration: reduce ? Duration.zero : kMotionDuration,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: border, width: kBorderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Disc(item: item, palette: palette, reduce: reduce),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                ),
                if (caption != null)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tabular(
                      AppText.caption.copyWith(
                        fontSize: 12,
                        height: 1.2,
                        color: overdue && !done ? _kOverdueInk : kInkSecondary,
                        fontWeight: overdue && !done ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      checked: item.isCount ? null : done,
      label: item.semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Pressable(onTap: onTap, onLongPress: onLongPress, child: chip),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.item, required this.palette, required this.reduce});

  final StripItem item;
  final AccentPalette palette;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final done = item.done;
    final overdue = item.overdue && !done;
    final iconColor = overdue ? _kOverdueInk : palette.lip;
    final Widget face = done
        ? Container(
            key: const ValueKey('done'),
            width: kChipDisc,
            height: kChipDisc,
            decoration: BoxDecoration(color: palette.fill, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 24, color: palette.onFill),
          )
        : Container(
            key: const ValueKey('open'),
            width: kChipDisc,
            height: kChipDisc,
            decoration: BoxDecoration(
              color: overdue ? _kOverdueDisc : palette.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(habitIcon(item.habit.icon), size: 20, color: iconColor),
          );
    final switcher = AnimatedSwitcher(
      duration: reduce ? Duration.zero : kPopDuration,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: face,
    );
    if (!item.isCount || done) {
      return SizedBox(width: kChipDisc, height: kChipDisc, child: switcher);
    }

    final target = item.habit.target ?? 1;
    return SizedBox(
      width: kChipDisc,
      height: kChipDisc,
      child: Stack(
        alignment: Alignment.center,
        children: [
          switcher,
          Positioned.fill(
            child: CircularProgressIndicator(
              value: (item.habit.count / target).clamp(0.0, 1.0),
              strokeWidth: 3,
              backgroundColor: kBorder,
              color: palette.fill,
              strokeCap: StrokeCap.round,
            ),
          ),
        ],
      ),
    );
  }
}
