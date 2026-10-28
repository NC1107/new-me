import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../state/meals_today.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../me/food_targets_page.dart';
import '../me/my_foods_page.dart';
import '../me/settings_row.dart';
import 'food_card.dart';

/// The Food tab: what was eaten today against the targets, today's meals, and the food settings.
class FoodScreen extends ConsumerWidget {
  const FoodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: CachedView<Today>(
        value: ref.watch(todayProvider),
        skeleton: const TodaySkeleton(),
        errorTitle: 'Could not load your food',
        onRetry: ref.read(todayProvider.notifier).refresh,
        builder: (context, today, offline) => _FoodBody(today: today),
      ),
    );
  }
}

class _FoodBody extends ConsumerWidget {
  const _FoodBody({required this.today});

  final Today today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = today.food.targets.kcal;
    return RefreshIndicator(
      color: context.accent,
      backgroundColor: kSurface,
      onRefresh: () async {
        await ref.read(todayProvider.notifier).refresh();
        ref.invalidate(mealsTodayProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
        children: [
          Semantics(header: true, child: const Text('Food', style: AppText.display)),
          const SizedBox(height: 16),
          FoodCard(food: today.food),
          const SizedBox(height: kCardGap),
          ChunkyButton(
            label: 'Log a meal',
            icon: Icons.add_rounded,
            onPressed: () => showLogSheet(context, kind: LogKind.meal),
          ),
          const SizedBox(height: 24),
          Semantics(header: true, child: const Text('Meals today', style: AppText.headline)),
          const SizedBox(height: 10),
          const _MealsToday(),
          const SizedBox(height: 24),
          SettingsGroup(
            rows: [
              SettingsRow(
                icon: Icons.restaurant_rounded,
                palette: accentById('green'),
                title: 'Food targets',
                subtitle: kcal == null ? 'Not set' : '${kcal.formatted} kcal a day',
                onTap: () => pushPage(context, const FoodTargetsPage()),
              ),
              SettingsRow(
                icon: Icons.bookmarks_rounded,
                palette: accentById('green'),
                title: 'My foods',
                subtitle: 'Saved foods with exact numbers',
                onTap: () => pushPage(context, const MyFoodsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealsToday extends ConsumerWidget {
  const _MealsToday();

  Future<void> _delete(BuildContext context, WidgetRef ref, MealLog meal) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(logActionsProvider);
    try {
      await actions.delete(meal);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${meal.name}'),
          persist: false,
          duration: kUndoWindow,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await actions.create(meal.toDraft(newClientOpId()));
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
              }
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(mealsTodayProvider)) {
      AsyncValue(:final value?) when value.isEmpty => Text(
        'Nothing logged yet today.',
        style: AppText.body.copyWith(color: kInkSecondary),
      ),
      AsyncValue(:final value?) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, m) in value.indexed) ...[
              if (i > 0) const Divider(height: 1, thickness: kBorderWidth, color: kBorder),
              _MealRow(meal: m, onDelete: () => _delete(context, ref, m)),
            ],
          ],
        ),
      ),
      AsyncValue(:final error?) => ErrorBlock(
        title: 'Could not load your meals',
        error: error,
        onRetry: () async => ref.invalidate(mealsTodayProvider),
      ),
      _ => const SkeletonBlock(height: 120, radius: kRadiusCard),
    };
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.onDelete});

  final MealLog meal;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm().format(meal.loggedAt.toLocal());
    final macros = '${meal.kcal.formatted} kcal · ${meal.protein.round()} g protein';
    return Semantics(
      container: true,
      label: '${meal.name}, $macros, $time',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meal.name, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      '$macros · $time',
                      style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 22),
              color: kInkMuted,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Delete ${meal.name}',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
