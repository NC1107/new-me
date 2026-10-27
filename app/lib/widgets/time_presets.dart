import 'package:flutter/material.dart';

import '../reminders/reminder_plan.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A row of equal time cards, the selected one tinted with the person's colour.
class TimePresets extends StatelessWidget {
  const TimePresets({
    super.key,
    required this.selected,
    required this.onChanged,
    this.minutes = kReminderPresetMinutes,
  });

  /// Minutes after midnight; a value outside [minutes] highlights nothing.
  final int selected;
  final ValueChanged<int> onChanged;
  final List<int> minutes;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Row(
      children: [
        for (final (i, value) in minutes.indexed) ...[
          if (i > 0) const SizedBox(width: kCardGap),
          Expanded(
            child: Builder(
              builder: (context) {
                final label = formatReminderTime(value);
                final on = value == selected;
                return Semantics(
                  button: true,
                  selected: on,
                  inMutuallyExclusiveGroup: true,
                  label: label,
                  excludeSemantics: true,
                  onTap: () => onChanged(value),
                  child: Pressable(
                    scale: 0.98,
                    onTap: () => onChanged(value),
                    child: AnimatedContainer(
                      duration: reduce ? Duration.zero : kMotionDuration,
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? palette.tint : kSurface,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: on ? palette.fill : kBorder, width: kBorderWidth),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: AppText.tabular(
                            AppText.headline.copyWith(fontSize: 17, color: on ? palette.lip : kInk),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
