import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';

/// Calories and macros eaten today. Not a quest and never scored.
class FoodCard extends StatelessWidget {
  const FoodCard({super.key, required this.food, required this.onTap, required this.onSetTargets});

  final Food food;
  final VoidCallback onTap;
  final VoidCallback onSetTargets;

  bool get _missingTargets => !food.targets.complete;

  @override
  Widget build(BuildContext context) {
    final kcalTarget = food.targets.kcal;
    return OnyxCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Food',
                style: TextStyle(color: kFgPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      kcalTarget == null
                          ? '${food.kcal.formatted} kcal'
                          : '${food.kcal.formatted} / ${kcalTarget.formatted} kcal',
                      style: const TextStyle(
                        color: kFgPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (kcalTarget != null && kcalTarget > 0) ...[
            const SizedBox(height: 10),
            ProgressBar(value: (food.kcal / kcalTarget).toDouble(), height: 4),
          ],
          const SizedBox(height: 12),
          _MacroRow(label: 'Protein', eaten: food.protein, target: food.targets.protein),
          const SizedBox(height: 6),
          _MacroRow(label: 'Carbs', eaten: food.carbs, target: food.targets.carbs),
          const SizedBox(height: 6),
          _MacroRow(label: 'Fat', eaten: food.fat, target: food.targets.fat),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_outlined, size: 14, color: kFgMuted),
                  const SizedBox(width: 4),
                  Text(
                    'burned ${food.burned.formatted}',
                    style: const TextStyle(
                      color: kFgMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_missingTargets)
                GestureDetector(
                  onTap: onSetTargets,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Set your targets',
                      style: TextStyle(
                        color: context.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.eaten, required this.target});

  final String label;
  final num eaten;
  final num? target;

  @override
  Widget build(BuildContext context) {
    final goal = target;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(color: kFgSecondary, fontSize: 13)),
        ),
        if (goal != null && goal > 0)
          Expanded(child: ProgressBar(value: (eaten / goal).toDouble(), height: 3))
        else
          const Spacer(),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(
            goal == null ? '${eaten.formatted} g' : '${eaten.formatted} / ${goal.formatted} g',
            textAlign: TextAlign.right,
            style: const TextStyle(color: kFgPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
