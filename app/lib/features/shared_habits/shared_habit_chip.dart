import 'package:flutter/material.dart';

import '../../api/shared_habit_models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/pressable.dart';
import '../habits/habit_chip.dart';
import '../habits/habit_icons.dart';
import 'shared_habit_text.dart';

const _kOverdueFill = Color(0xFFFFF3E0);
const _kOverdueDisc = Color(0xFFFFE0B2);
const _kOverdueInk = Color(0xFF8A4B00);

/// A shared chore as a chip in Today's habit strip. It looks like a personal habit chip, with a
/// small people badge on the icon so it is clear it belongs to both of you.
class SharedHabitChip extends StatelessWidget {
  const SharedHabitChip({super.key, required this.habit, required this.onTap});

  final SharedHabit habit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final h = habit;
    final done = h.doneToday;
    final overdue = h.overdue && !done;
    final Color fill = done ? palette.tint : (overdue ? _kOverdueFill : kSurface);
    final Color border = done ? palette.fill : (overdue ? kFlame : kBorder);
    final caption = done
        ? (h.doneByMe ? 'Done by you' : 'Done by ${h.last?.name ?? 'your partner'}')
        : (overdue ? sharedDueLabel(h).replaceFirst('Overdue by ', 'Overdue ') : 'Shared');
    final label = '${h.name}, shared, ${done ? 'done' : sharedDueLabel(h)}';
    return Semantics(
      button: true,
      checked: done,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
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
              _Disc(habit: h, palette: palette, overdue: overdue),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tabular(
                        AppText.caption.copyWith(
                          fontSize: 12,
                          height: 1.2,
                          color: overdue ? _kOverdueInk : kInkSecondary,
                          fontWeight: overdue ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.habit, required this.palette, required this.overdue});

  final SharedHabit habit;
  final AccentPalette palette;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final done = habit.doneToday;
    return SizedBox(
      width: kChipDisc,
      height: kChipDisc,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: kChipDisc,
            height: kChipDisc,
            decoration: BoxDecoration(
              color: done ? palette.fill : (overdue ? _kOverdueDisc : palette.tint),
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check_rounded : habitIcon(habit.icon),
              size: done ? 24 : 20,
              color: done ? palette.onFill : (overdue ? _kOverdueInk : palette.lip),
            ),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: kSurface,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder, width: 1.5),
              ),
              child: const Icon(Icons.people_alt_rounded, size: 10, color: kInkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
