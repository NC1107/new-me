import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/board.dart';
import '../../state/companion.dart';
import '../../state/habit_reminders.dart';
import '../../state/health_sync.dart';
import '../../state/listening_sync.dart';
import '../../state/me.dart';
import '../../state/push.dart';
import '../../state/reminders.dart';
import '../../state/right_now.dart';
import '../../state/together_seen.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/pressable.dart';
import '../board/board_screen.dart';
import '../food/food_screen.dart';
import '../training/train_screen.dart';
import '../me/me_screen.dart';
import '../today/today_screen.dart';
import 'home_tab.dart';
import '../../state/health_history.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Reading the provider is what starts Health sync and its lifecycle listener.
    ref.read(healthSyncProvider);
    ref.read(remindersProvider);
    ref.read(habitRemindersProvider);
    ref.read(pushProvider);
    ref.read(companionProvider);
    unawaited(_followDeviceTimezone());
    // History resumes each launch, and starts as soon as Health is connected.
    unawaited(ref.read(healthHistoryProvider.notifier).run());
    ref.listenManual(healthSyncProvider.select((h) => h.prompted), (was, now) {
      if (now && was != true) unawaited(ref.read(healthHistoryProvider.notifier).run());
    });
    unawaited(ref.read(listeningSyncProvider).syncThenRefreshToday(onlyIfSynced: true));
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// A screen drawn from the cache stays under its offline banner until something reloads it.
  void _refreshOffline() {
    if (ref.read(todayProvider).value?.offline != null) {
      unawaited(ref.read(todayProvider.notifier).refresh());
    }
    if (ref.read(boardProvider).value?.offline != null) {
      unawaited(ref.read(boardProvider.notifier).refresh());
    }
    if (ref.read(meProvider).value?.offline != null) {
      unawaited(ref.read(meProvider.notifier).refresh());
    }
  }

  /// A phone left locked overnight would otherwise open on yesterday's score.
  void _onResume() {
    unawaited(ref.read(remindersProvider.notifier).refreshPermission());
    unawaited(_refreshTodayThenSync());
    unawaited(ref.read(boardProvider.notifier).refresh());
    unawaited(_followDeviceTimezone());
    // A phone left open over midnight may now be on a Monday, or past Sunday 19:00.
    ref.invalidate(goalProposalsProvider);
    ref.invalidate(recapProvider);
    if (ref.read(meProvider).value?.offline != null) {
      unawaited(ref.read(meProvider.notifier).refresh());
    }
  }

  /// Today comes first so a slow Audiobookshelf sync never holds the screen on yesterday.
  Future<void> _refreshTodayThenSync() async {
    await ref.read(todayProvider.notifier).refresh();
    await ref.read(listeningSyncProvider).syncThenRefreshToday(onlyIfSynced: true);
  }

  Future<void> _followDeviceTimezone() async {
    try {
      final changed = await ref.read(meProvider.notifier).syncDeviceTimezone();
      if (changed && mounted) {
        await ref.read(remindersProvider.notifier).deviceTimezoneChanged();
        await ref.read(habitRemindersProvider.notifier).deviceTimezoneChanged();
      }
    } on Object catch (e) {
      debugPrint('[NEWME] timezone sync skipped: $e');
    }
    try {
      await ref.read(meProvider.notifier).fillUnitsFromRegion();
    } on Object catch (e) {
      debugPrint('[NEWME] units fill skipped: $e');
    }
  }

  static const _tabs = [
    (icon: Icons.home_rounded, label: 'Today'),
    (icon: Icons.restaurant_rounded, label: 'Food'),
    (icon: Icons.fitness_center_rounded, label: 'Train'),
    (icon: Icons.groups_rounded, label: 'Us'),
    (icon: Icons.person_rounded, label: 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    final usBadge = ref.watch(usBadgeProvider);
    ref.listen(homeTabProvider, (_, _) => _refreshOffline());
    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [TodayScreen(), FoodScreen(), TrainScreen(), BoardScreen(), MeScreen()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(
            top: BorderSide(color: kBorder, width: kBorderWidth),
          ),
        ),
        child: SafeArea(
          top: false,
          // The bar has a fixed height, so a large Dynamic Type size would overflow its labels.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: kBottomNavMaxTextScale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: _NavItem(
                          key: Key('nav-${_tabs[i].label.toLowerCase()}'),
                          icon: _tabs[i].icon,
                          label: _tabs[i].label,
                          selected: tab.index == i,
                          badge: _tabs[i].label == 'Us' && usBadge,
                          onTap: () => ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab: icon over label. Selected, it sits in a rounded square tinted and bordered in the
/// person's colour.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A dot on the icon: something new is waiting behind this tab.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final color = selected ? context.accentText : kInkMuted;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: badge ? '$label, something new' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        haptic: false,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Center(
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : kMotionDuration,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? person.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(kRadiusButton),
              border: Border.all(
                color: selected ? person.fill : Colors.transparent,
                width: kBorderWidth,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: kBottomNavIconSize, color: color),
                    if (badge)
                      Positioned(
                        right: -3,
                        top: -2,
                        child: Container(
                          key: const Key('nav-badge'),
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: kDanger,
                            shape: BoxShape.circle,
                            border: Border.all(color: kSurface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: kBottomNavIconLabelGap),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: kBottomNavLabelStyle.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
