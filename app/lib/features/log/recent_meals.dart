import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';
import 'log_panes.dart';

/// The list's height before it scrolls: about four and a half rows, so a cut row says there is
/// more and the form below stays in reach.
const kRecentMealsHeight = 272.0;

/// Whether [meal] matches every word of [query], so "turkey cheese" finds the sandwich.
bool recentMealMatches(RecentMeal meal, String query) {
  final name = meal.name.toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(name.contains);
}

/// The newest meals either person logged, one per row in a box of their own that scrolls,
/// narrowed to what is typed in the search box. Rows, not chips, because the names are often
/// whole ingredient lists that a chip cuts down to the same first words.
class RecentMeals extends StatelessWidget {
  const RecentMeals({
    super.key,
    required this.meals,
    required this.enabled,
    required this.onLog,
    this.query = '',
  });

  final List<RecentMeal> meals;
  final String query;
  final bool enabled;
  final ValueChanged<RecentMeal> onLog;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final meal in meals)
        if (recentMealMatches(meal, query)) meal,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Recent meals, tap to log'),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: kBorder, width: kBorderWidth),
            borderRadius: BorderRadius.circular(kRadiusField),
          ),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'No recent meal matches',
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: kRecentMealsHeight),
                  child: Scrollbar(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => RecentMealTile(
                        meal: shown[i],
                        enabled: enabled,
                        onTap: () => onLog(shown[i]),
                      ),
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
