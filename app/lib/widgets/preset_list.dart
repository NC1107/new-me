import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

class Preset<T> {
  const Preset({required this.name, required this.valueLabel, required this.value});

  /// "Casual"
  final String name;

  /// "5,000 steps"
  final String valueLabel;
  final T value;
}

/// A vertical list of named presets with one selected, in the style of Duolingo's daily goal.
class PresetList<T> extends StatelessWidget {
  const PresetList({
    super.key,
    required this.presets,
    required this.selected,
    required this.onChanged,
    this.palette,
  });

  final List<Preset<T>> presets;
  final T? selected;
  final ValueChanged<T> onChanged;
  final AccentPalette? palette;

  @override
  Widget build(BuildContext context) {
    final person = palette ?? context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < presets.length; i++) ...[
          if (i > 0) const SizedBox(height: kCardGap),
          Builder(
            builder: (context) {
              final preset = presets[i];
              final on = preset.value == selected;
              return Semantics(
                button: true,
                selected: on,
                inMutuallyExclusiveGroup: true,
                label: '${preset.name}, ${preset.valueLabel}',
                excludeSemantics: true,
                onTap: () => onChanged(preset.value),
                child: Pressable(
                  scale: 0.98,
                  onTap: () => onChanged(preset.value),
                  child: AnimatedContainer(
                    duration: reduce ? Duration.zero : kMotionDuration,
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: on ? person.tint : kSurface,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: on ? person.fill : kBorder, width: kBorderWidth),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(preset.name, style: AppText.headline.copyWith(fontSize: 18)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              preset.valueLabel,
                              maxLines: 1,
                              style: AppText.tabular(
                                AppText.body.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: on ? person.lip : kInkSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
