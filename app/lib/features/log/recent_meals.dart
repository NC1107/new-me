import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';
import 'log_panes.dart';

/// How many recent meals show before "Show more", so the form below stays in reach.
const kRecentMealsShown = 5;

/// The newest meals either person logged, one per row, because their names are often whole
/// ingredient lists that a chip cuts down to the same first words.
class RecentMeals extends StatefulWidget {
  const RecentMeals({super.key, required this.meals, required this.enabled, required this.onLog});

  final List<RecentMeal> meals;
  final bool enabled;
  final ValueChanged<RecentMeal> onLog;

  @override
  State<RecentMeals> createState() => _RecentMealsState();
}

class _RecentMealsState extends State<RecentMeals> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final meals = widget.meals;
    final hidden = meals.length - kRecentMealsShown;
    final shown = _all || hidden <= 0 ? meals : meals.take(kRecentMealsShown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Recent meals, tap to log'),
        for (final meal in shown)
          RecentMealTile(meal: meal, enabled: widget.enabled, onTap: () => widget.onLog(meal)),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: () => setState(() => _all = !_all),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _all ? 'Show fewer' : 'Show $hidden more',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                    Icon(
                      _all ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 24,
                      color: kInkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class RecentMealTile extends StatelessWidget {
  const RecentMealTile({super.key, required this.meal, required this.enabled, required this.onTap});

  final RecentMeal meal;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = '${meal.kcal.formatted} kcal · ${gramsText(meal.protein)} g protein';
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${meal.name}, $details',
      hint: 'Logs it',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Pressable(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(details, style: AppText.caption.copyWith(color: kInkSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.add_circle_outline_rounded, size: 28, color: kInkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
