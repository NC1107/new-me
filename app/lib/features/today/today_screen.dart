import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/local_prefs.dart';
import '../../state/session.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/quest_card.dart';
import '../health/health_screen.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../shell/home_tab.dart';
import 'body_card.dart';
import 'connect_health_card.dart';
import 'day_card.dart';
import 'day_counted_sheet.dart';
import 'day_detail_sheet.dart';
import 'food_card.dart';
import 'streak_sheet.dart';
import 'today_header.dart';
import 'today_providers.dart';
import 'today_skeleton.dart';
import 'today_top_bar.dart';
import 'week_card.dart';

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
        builder: (context, today, offline) => _TodayBody(today: today, offline: offline),
      ),
    );
  }
}

class _TodayBody extends ConsumerStatefulWidget {
  const _TodayBody({required this.today, required this.offline});

  final Today today;
  final bool offline;

  @override
  ConsumerState<_TodayBody> createState() => _TodayBodyState();
}

class _TodayBodyState extends ConsumerState<_TodayBody> {
  String? _celebrationHandled;

  Today get today => widget.today;

  Future<void> _refresh() async {
    await ref.read(healthSyncProvider.notifier).sync(SyncTrigger.manual);
    await ref.read(todayProvider.notifier).refresh();
  }

  /// Plays the day-counted sheet once per date. It waits for the Today tab and for any sheet that
  /// is still closing (a log sheet pops right after the save that made the day count).
  void _maybeCelebrate(bool onToday) {
    if (!onToday || widget.offline || !today.day.counted) return;
    if (_celebrationHandled == today.localToday) return;
    final date = today.localToday;
    _celebrationHandled = date;
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate(date));
  }

  Future<void> _celebrate(String date) async {
    if (await LocalPrefs.celebratedDate() == date) return;
    for (var i = 0; i < 40; i++) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    await LocalPrefs.setCelebratedDate(date);
    if (!mounted) return;
    await showDayCountedSheet(context);
  }

  void _openEntries() => showDayDetailSheet(context, date: today.localToday);

  void _openHealth() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HealthScreen()));

  @override
  Widget build(BuildContext context) {
    final onToday = ref.watch(homeTabProvider) == HomeTab.today;
    _maybeCelebrate(onToday);

    final name = ref.watch(sessionProvider.select((s) => s.session?.userName)) ?? '';
    final prompted = ref.watch(healthSyncProvider.select((s) => s.prompted));
    final lastSynced = ref.watch(healthSyncProvider.select((s) => s.lastSyncedAt));
    final syncedAt = today.health.syncedAt ?? lastSynced;
    final now = ref.watch(clockProvider)();
    final partner = ref.watch(partnerProvider);
    final mine = ref.watch(ownBoardUserProvider);
    final weight = ref.watch(weightTrendProvider).value;
    final tabs = ref.read(homeTabProvider.notifier);
    final tiles = bodyTiles(today.health, today.localToday, weight);

    return RefreshIndicator(
      color: context.accent,
      backgroundColor: kSurface,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
        children: [
          TodayTopBar(
            name: name,
            palette: context.accentPalette,
            streak: today.streak.current,
            points: today.day.points,
            partner: partner,
            onOpenMe: () => tabs.select(HomeTab.me),
            onOpenUs: () => tabs.select(HomeTab.board),
            onStreak: () =>
                showStreakSheet(context, streak: today.streak, line: today.day.streakLine),
          ),
          const SizedBox(height: 12),
          TodayHeader(today: today, name: name, now: now),
          const SizedBox(height: 16),
          DayCard(day: today.day, streak: today.streak, onEntries: _openEntries),
          ..._questCards(prompted),
          const SizedBox(height: kCardGap),
          FoodCard(
            food: today.food,
            onTap: () => showLogSheet(context, kind: LogKind.meal),
            onSetTargets: () => tabs.select(HomeTab.me),
          ),
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: kCardGap),
            BodyCard(tiles: tiles, onTap: _openHealth),
          ],
          if (mine != null && mine.last7.isNotEmpty) ...[
            const SizedBox(height: kCardGap),
            WeekCard(days: mine.last7, today: today.localToday, todayCounted: today.day.counted),
          ],
          if (syncedAt != null) ...[
            const SizedBox(height: 20),
            Center(
              child: Text('Health synced ${relativeTime(syncedAt, now)}', style: AppText.caption),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _questCards(bool prompted) {
    final cards = <Widget>[];
    var connectShown = false;
    Widget connect() => ConnectHealthCard(
      prompted: prompted,
      onConnect: () => ref.read(healthSyncProvider.notifier).connect(),
    );

    for (final q in today.quests) {
      cards.add(const SizedBox(height: kCardGap));
      if (q.key == 'steps' && !today.health.stepsEverSynced) {
        cards.add(connect());
        connectShown = true;
      } else {
        final kind = LogKind.forQuest(q.key);
        cards.add(
          QuestCard(
            key: ValueKey(q.key),
            quest: q,
            onTap: _openEntries,
            onAdd: kind == null ? null : () => showLogSheet(context, kind: kind),
            listeningMinutes: q.key == 'reading' ? today.listeningMinutes : 0,
          ),
        );
      }
    }
    if (!today.health.stepsEverSynced && !connectShown) {
      cards.insert(0, connect());
      cards.insert(0, const SizedBox(height: kCardGap));
    }
    return cards;
  }
}
