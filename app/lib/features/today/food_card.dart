import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/pressable.dart';
import '../../widgets/thick_progress_bar.dart';
import 'mini_bar.dart';

/// Calories and macros eaten today. Not a quest and never scored; tapping it logs a meal.
class FoodCard extends StatelessWidget {
  const FoodCard({super.key, required this.food, required this.onTap, required this.onSetTargets});

  final Food food;
  final VoidCallback onTap;
  final VoidCallback onSetTargets;

  @override
  Widget build(BuildContext context) {
    final kcalTarget = food.targets.kcal;
    final palette = questPalette('meals_logged');
    final wide = MediaQuery.textScalerOf(context).scale(13) <= 18;
    final macros = [
      _Macro('Protein', food.protein, food.targets.protein, questPalette('protein').fill),
      _Macro('Carbs', food.carbs, food.targets.carbs, questPalette('pushups').fill),
      _Macro('Fat', food.fat, food.targets.fat, questPalette('exercise').fill),
    ];

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(questIcon('meals_logged'), size: 26, color: palette.lip),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Food', style: AppText.headline.copyWith(fontSize: 17)),
                    Text(
                      kcalTarget == null
                          ? '${food.kcal.formatted} kcal'
                          : '${food.kcal.formatted} of ${kcalTarget.formatted} kcal',
                      style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                    ),
                  ],
                ),
              ),
              ChunkyIconButton(
                icon: Icons.add_rounded,
                semanticLabel: 'Log a meal',
                onPressed: onTap,
              ),
            ],
          ),
          if (kcalTarget != null && kcalTarget > 0) ...[
            const SizedBox(height: 12),
            ThickProgressBar(value: (food.kcal / kcalTarget).toDouble(), color: palette.fill),
          ],
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < macros.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: macros[i]),
                ],
              ],
            )
          else
            for (var i = 0; i < macros.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              macros[i],
            ],
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 16, color: kInkMuted),
                    const SizedBox(width: 4),
                    Text('burned ${food.burned.formatted}', style: AppText.caption),
                  ],
                ),
              ),
              if (!food.targets.complete)
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Set your targets',
                  onTap: onSetTargets,
                  child: Pressable(
                    onTap: onSetTargets,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          'Set your targets',
                          style: AppText.label.copyWith(color: context.accentText),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.eaten, this.target, this.color);

  final String label;
  final num eaten;
  final num? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final goal = target;
    final value = goal == null
        ? '${eaten.formatted} g'
        : '${eaten.formatted} / ${goal.formatted} g';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 4),
        MiniBar(value: goal == null || goal <= 0 ? 0 : (eaten / goal).toDouble(), color: color),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppText.tabular(AppText.label)),
        ),
      ],
    );
  }
}
