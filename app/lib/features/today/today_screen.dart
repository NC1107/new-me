import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/insights.dart';
import '../../state/listening_sync.dart';
import '../../state/local_prefs.dart';
import '../../state/right_now.dart';
import '../../state/session.dart';
import '../../state/today.dart';
import '../../state/training.dart';
import '../../state/units.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/quest_card.dart';
import '../../widgets/quest_copy.dart';
import '../habits/habits_strip.dart';
import '../insights/insights_screen.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../progress/milestone_celebration.dart';
import '../shell/home_tab.dart';
import '../streaks/away_line.dart';
import '../streaks/away_page.dart';
import '../training/training_card.dart';
import 'body_card.dart';
import 'connect_health_card.dart';
import 'day_card.dart';
import 'day_counted_sheet.dart';
import 'day_detail_sheet.dart';
import 'plan_sheet.dart';
import 'quest_sheet.dart';
import 'right_now.dart';
import 'streak_sheet.dart';
import 'turned_off_quests.dart';
import 'today_header.dart';
import 'today_providers.dart';
import 'today_skeleton.dart';
import 'today_top_bar.dart';

/// How long Health may go without syncing before Today mentions it.
const kHealthStaleAfter = Duration(hours: 12);

/// More than this at once is a flood; the rest are marked seen without playing.
const kMaxMilestoneCelebrations = 3;

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
  bool _milestonesRunning = false;

  Today get today => widget.today;

  Future<void> _refresh() async {
    await ref.read(healthSyncProvider.notifier).sync(SyncTrigger.manual);
    await ref.read(listeningSyncProvider).syncThenRefreshToday();
    if (ref.exists(insightsProvider)) await ref.read(insightsProvider.notifier).refresh();
    if (ref.exists(trainingTodayProvider)) await ref.read(trainingTodayProvider.notifier).refresh();
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

  /// Plays each new milestone full screen, once per phone, after anything already on screen has
  /// closed. They are marked seen as they play, so a rebuild never replays one.
  void _maybeCelebrateMilestones(bool onToday) {
    if (!onToday || widget.offline || _milestonesRunning || today.newMilestones.isEmpty) return;
    final memory = ref.read(rightNowMemoryProvider);
    if (!memory.loaded) return;
    final unseen = [
      for (final m in today.newMilestones)
        if (!memory.has(milestoneSeenKey(m.id))) m,
    ];
    if (unseen.isEmpty) return;
    _milestonesRunning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebrateMilestones(unseen));
  }

  Future<void> _celebrateMilestones(List<Milestone> milestones) async {
    try {
      for (final m in milestones.take(kMaxMilestoneCelebrations)) {
        for (var i = 0; i < 40; i++) {
          if (!mounted) return;
          final route = ModalRoute.of(context);
          if (route == null || route.isCurrent) break;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (!mounted) return;
        await ref.read(rightNowMemoryProvider.notifier).dismiss(milestoneSeenKey(m.id));
        if (!mounted) return;
        await showMilestoneCelebration(context, m);
      }
      for (final m in milestones.skip(kMaxMilestoneCelebrations)) {
        await ref.read(rightNowMemoryProvider.notifier).dismiss(milestoneSeenKey(m.id));
      }
    } finally {
      _milestonesRunning = false;
    }
  }

  void _openAway() => pushPage(context, const AwayPage());

  void _openEntries() => showDayDetailSheet(context, date: today.localToday);

  Future<void> _openQuest(String key) async {
    final title = today.quests.where((q) => q.key == key).firstOrNull?.title ?? 'Quest';
    final messenger = ScaffoldMessenger.of(context);
    final result = await showQuestSheet(context, questKey: key);
    if (result != QuestSheetResult.turnedOff) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$title is off'),
          persist: false,
          duration: kUndoWindow,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => setQuestEnabled(ref, key, true).ignore(),
          ),
        ),
      );
  }

  void _openPlan() {
    final plan = today.plan;
    if (plan != null) showPlanSheet(context, plan: plan, readiness: today.readiness);
  }

  @override
  Widget build(BuildContext context) {
    final onToday = ref.watch(homeTabProvider) == HomeTab.today;
    _maybeCelebrate(onToday);
    ref.watch(rightNowMemoryProvider);
    _maybeCelebrateMilestones(onToday);

    final name = ref.watch(sessionProvider.select((s) => s.session?.userName)) ?? '';
    final prompted = ref.watch(healthSyncProvider.select((s) => s.prompted));
    final lastSynced = ref.watch(healthSyncProvider.select((s) => s.lastSyncedAt));
    final syncedAt = today.health.syncedAt ?? lastSynced;
    final now = ref.watch(clockProvider)();
    final partner = ref.watch(partnerProvider);
    final tabs = ref.read(homeTabProvider.notifier);
    final insights = ref.watch(insightsProvider).value?.data;

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
            onStreak: () => showStreakSheet(
              context,
              streak: today.streak,
              line: today.day.streakLine,
              freezes: today.freezes,
              onAway: _openAway,
            ),
          ),
          const SizedBox(height: 12),
          TodayHeader(
            today: today,
            name: name,
            now: now,
            onPlan: today.plan == null ? null : _openPlan,
          ),
          const SizedBox(height: 16),
          DayCard(
            day: today.day,
            streak: today.streak,
            quests: today.quests,
            onEntries: _openEntries,
          ),
          RightNowSlot(today: today),
          if (today.away.today) ...[
            const SizedBox(height: kCardGap),
            AwayLine(away: today.away, onOpen: _openAway),
          ],
          HabitsStrip(today: today),
          TrainingSlot(localToday: today.localToday, onTrainTab: false),
          ..._questCards(prompted, now),
          const SizedBox(height: kCardGap),
          BodyRow(
            summary: bodySummary(today.health, insights),
            weight: insights?.weight,
            onTap: () => openInsights(context),
          ),
          // Sync is quiet when it works; the line shows only once Health has been silent a while.
          if (syncedAt != null && now.difference(syncedAt) > kHealthStaleAfter) ...[
            const SizedBox(height: 20),
            Center(
              child: Text('Health synced ${relativeTime(syncedAt, now)}', style: AppText.caption),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _questCards(bool prompted, DateTime now) {
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
            units: ref.watch(unitsProvider),
            onTap: () => _openQuest(q.key),
            onAdd: kind == null ? null : () => showLogSheet(context, kind: kind),
            listeningMinutes: q.key == 'reading' ? today.listeningMinutes : 0,
            listeningNote: q.key == 'reading' && today.listeningSyncedAt != null
                ? listeningSyncedLabel(today.listeningSyncedAt!, now)
                : null,
          ),
        );
      }
    }
    if (today.quests.any((q) => isAutomaticQuest(q.key))) {
      cards.add(const SizedBox(height: 12));
      cards.add(const HealthNote());
    }
    cards.add(const TurnedOffRow());
    if (!today.health.stepsEverSynced && !connectShown) {
      cards.insert(0, connect());
      cards.insert(0, const SizedBox(height: kCardGap));
    }
    return cards;
  }
}
