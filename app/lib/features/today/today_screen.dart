import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/local_prefs.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/quest_card.dart';
import '../../widgets/score_ring.dart';
import '../../widgets/skeletons.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../shell/home_tab.dart';
import 'day_detail_sheet.dart';
import 'food_card.dart';

/// True the first time a local date is shown, so the ring counts up once a day and not on every
/// open. Reading it records the date.
final firstViewOfDayProvider = FutureProvider.family<bool, String>((ref, date) async {
  if (await LocalPrefs.countUpDate() == date) return false;
  await LocalPrefs.setCountUpDate(date);
  return true;
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(todayProvider.notifier);
    return SafeArea(
      bottom: false,
      child: CachedView<Today>(
        value: ref.watch(todayProvider),
        skeleton: const TodaySkeleton(),
        errorTitle: 'Could not load today',
        onRetry: notifier.refresh,
        builder: (context, today, offline) => _TodayBody(today: today),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.today});

  final Today today;

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(healthSyncProvider.notifier).sync(SyncTrigger.manual);
    await ref.read(todayProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countUp = ref.watch(firstViewOfDayProvider(today.localToday));
    if (countUp.value == null) return const TodaySkeleton();

    final prompted = ref.watch(healthSyncProvider.select((s) => s.prompted));
    final lastSynced = ref.watch(healthSyncProvider.select((s) => s.lastSyncedAt));
    final syncedAt = today.health.syncedAt ?? lastSynced;

    return RefreshIndicator(
      color: context.accent,
      backgroundColor: kBgSurface,
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(parseLocalDate(today.localToday)),
            style: const TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Center(
            child: ScoreRing(
              points: today.day.points,
              percent: today.day.percent,
              threshold: today.day.threshold,
              countUp: countUp.requireValue,
            ),
          ),
          const SizedBox(height: 14),
          Center(child: _StreakLine(day: today.day)),
          const SizedBox(height: 12),
          Center(
            child: _StreakRow(streak: today.streak, threshold: today.day.threshold),
          ),
          if (_isEmpty(today)) ...[
            const SizedBox(height: 14),
            const Center(
              child: Text('Nothing yet today.', style: TextStyle(color: kFgMuted, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          ..._questCards(context, ref, prompted),
          FoodCard(
            food: today.food,
            onTap: () => showDayDetailSheet(context, date: today.localToday),
            onSetTargets: () => ref.read(homeTabProvider.notifier).select(HomeTab.me),
          ),
          if (syncedAt != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Health synced ${relativeTime(syncedAt, ref.watch(clockProvider)())}',
                style: const TextStyle(color: kFgMuted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isEmpty(Today t) =>
      t.day.points == 0 && t.food.kcal == 0 && t.quests.every((q) => q.actual == 0);

  List<Widget> _questCards(BuildContext context, WidgetRef ref, bool prompted) {
    final cards = <Widget>[];
    var connectShown = false;
    Widget connect() => ConnectHealthCard(
      prompted: prompted,
      onConnect: () => ref.read(healthSyncProvider.notifier).connect(),
    );

    for (final q in today.quests) {
      if (q.key == 'steps' && !today.health.hasSteps) {
        cards.add(connect());
        connectShown = true;
      } else {
        final kind = LogKind.forQuest(q.key);
        cards.add(
          QuestCard(
            quest: q,
            onTap: () => showDayDetailSheet(context, date: today.localToday),
            onAdd: kind == null ? null : () => showLogSheet(context, kind: kind),
          ),
        );
      }
      cards.add(const SizedBox(height: 10));
    }
    if (!today.health.hasSteps && !connectShown) {
      cards.insert(0, const SizedBox(height: 10));
      cards.insert(0, connect());
    }
    return cards;
  }
}

class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.day});

  final DayScore day;

  @override
  Widget build(BuildContext context) => day.counted
      ? Text(
          'Streak day counted',
          style: TextStyle(color: context.accent, fontSize: 14, fontWeight: FontWeight.w700),
        )
      : Text(
          'Streak line: ${day.threshold}% - you are at ${day.percent}%',
          style: const TextStyle(color: kFgSecondary, fontSize: 14, fontWeight: FontWeight.w600),
        );
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.streak, required this.threshold});

  final Streak streak;
  final int threshold;

  String? get _restLabel {
    final used = streak.restUsedOn;
    if (used != null) return 'Rest day used ${weekdayShort(used)}';
    return streak.restAvailable ? 'Rest day ready' : null;
  }

  @override
  Widget build(BuildContext context) {
    final rest = _restLabel;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _Pill(
          icon: Icons.local_fire_department_outlined,
          label: 'Day ${streak.current < 1 ? 1 : streak.current}',
          color: context.accent,
          background: context.accentLight,
          onTap: () => _open(context),
        ),
        if (rest != null)
          _Pill(
            icon: Icons.bedtime_outlined,
            label: rest,
            color: kFgSecondary,
            background: kBgSurface,
            outlined: true,
            onTap: () => _open(context),
          ),
      ],
    );
  }

  void _open(BuildContext context) {
    HapticFeedback.selectionClick();
    showAppSheet<void>(
      context,
      builder: (_) => _StreakSheet(streak: streak, threshold: threshold),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9999),
          border: outlined ? Border.all(color: kBorder) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StreakSheet extends StatelessWidget {
  const _StreakSheet({required this.streak, required this.threshold});

  final Streak streak;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final used = streak.restUsedOn;
    final status = used != null
        ? 'Rest day used ${weekdayShort(used)}'
        : streak.restAvailable
        ? 'Rest day ready'
        : 'No rest day left this week';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Day ${streak.current < 1 ? 1 : streak.current}',
              style: const TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'A day counts toward your streak when you reach the streak line, $threshold% of '
              'the day. The streak is how many counted days you have in a row.',
              style: const TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'One missed day a week is forgiven. That is your rest day: it keeps the streak but '
              'does not add to it. It only works if the day before was not also missed, and it '
              'does not carry over to the next week.',
              style: TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            OnyxCard(
              child: Row(
                children: [
                  const Icon(Icons.bedtime_outlined, size: 18, color: kFgSecondary),
                  const SizedBox(width: 10),
                  Text(
                    status,
                    style: const TextStyle(
                      color: kFgPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
