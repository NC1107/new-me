import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/thick_progress_bar.dart';
import '../today/mini_bar.dart';

/// Calories and macros eaten today, at the top of the Food tab. Not a quest and never scored.
class FoodCard extends StatelessWidget {
  const FoodCard({super.key, required this.food});

  final Food food;

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
    final left = kcalTarget == null ? null : kcalTarget - food.kcal;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  kcalTarget == null
                      ? '${food.kcal.formatted} kcal'
                      : '${food.kcal.formatted} of ${kcalTarget.formatted} kcal',
                  style: AppText.tabular(AppText.headline),
                ),
              ),
              if (left != null)
                Text(
                  left >= 0 ? '${left.formatted} left' : '${(-left).formatted} over',
                  style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                ),
            ],
          ),
          if (kcalTarget != null && kcalTarget > 0) ...[
            const SizedBox(height: 10),
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
          if (food.burned > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, size: 16, color: kInkMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${food.burned.formatted} kcal burned in activity',
                    style: AppText.tabular(AppText.caption),
                  ),
                ),
              ],
            ),
          ],
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
        if (goal != null && goal > 0) ...[
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              eaten > goal
                  ? '${(eaten - goal).round().formatted} g over'
                  : '${(goal - eaten).round().formatted} g left',
              style: AppText.tabular(AppText.caption),
            ),
          ),
        ],
      ],
    );
  }
}
