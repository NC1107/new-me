import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/foods.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../log/food_search.dart';
import 'food_edit_page.dart';

/// Foods saved for the household, so the same food has the same numbers every time.
class MyFoodsPage extends ConsumerWidget {
  const MyFoodsPage({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, [SavedFood? food]) =>
      pushPage(context, FoodEditPage(food: food));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foods = ref.watch(foodLibraryProvider);
    return PageScaffold(
      title: 'My foods',
      children: [
        Text(
          'Saved foods always log with the same numbers.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        FoodSearchBox(
          browseOnFocus: false,
          onPick: (food) => _open(context, ref, food),
          onEnterByHand: () => _open(context, ref),
        ),
        const SizedBox(height: 16),
        ChunkyButton.secondary(
          label: 'New food',
          icon: Icons.add_rounded,
          onPressed: () => _open(context, ref),
        ),
        const SizedBox(height: 16),
        ...switch (foods) {
          AsyncData(:final value) when value.isEmpty => [
            Text(
              'Nothing saved yet. Search, scan a barcode or add a new food, and it keeps its '
              'exact numbers here.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
          ],
          AsyncData(:final value) => [
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, food) in value.indexed) ...[
                    if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                    _FoodRow(food: food, onTap: () => _open(context, ref, food)),
                  ],
                ],
              ),
            ),
          ],
          AsyncError(:final error) => [
            ErrorBlock(
              title: 'Could not load your foods',
              error: error,
              onRetry: () async => ref.invalidate(foodLibraryProvider),
            ),
          ],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onTap});

  final SavedFood food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [
      food.servingText,
      '${food.kcal.formatted} kcal',
      if (food.useCount > 0) 'used ${food.useCount} ${food.useCount == 1 ? 'time' : 'times'}',
    ].join(' · ');
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${food.title}, $detail',
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: kInkSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: kInkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
