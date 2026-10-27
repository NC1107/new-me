import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/board.dart';
import '../../state/health_sync.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../board/board_screen.dart';
import '../log/log_sheet.dart';
import '../me/me_screen.dart';
import '../today/today_screen.dart';
import 'home_tab.dart';

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
    unawaited(_followDeviceTimezone());
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
    unawaited(ref.read(todayProvider.notifier).refresh());
    unawaited(ref.read(boardProvider.notifier).refresh());
    if (ref.read(meProvider).value?.offline != null) {
      unawaited(ref.read(meProvider.notifier).refresh());
    }
  }

  Future<void> _followDeviceTimezone() async {
    try {
      await ref.read(meProvider.notifier).syncDeviceTimezone();
    } on Object catch (e) {
      debugPrint('[NEWME] timezone sync skipped: $e');
    }
  }

  static const _tabs = [
    (icon: Icons.today_outlined, activeIcon: Icons.today_rounded, label: 'Today'),
    (icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard_rounded, label: 'Board'),
    (icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    ref.listen(homeTabProvider, (_, _) => _refreshOffline());
    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [TodayScreen(), BoardScreen(), MeScreen()],
      ),
      floatingActionButton: SizedBox(
        height: 58,
        width: 58,
        child: FloatingActionButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            showLogSheet(context);
          },
          backgroundColor: context.accent,
          foregroundColor: context.onAccent,
          elevation: 4,
          tooltip: 'Log',
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: kBgMain,
        elevation: 0,
        height: 64,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        notchMargin: 9,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kBorder)),
          ),
          // The bar has a fixed height, so a large Dynamic Type size would overflow its labels.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: kBottomNavMaxTextScale,
            child: Row(
              children: [
                Expanded(child: Row(children: [_item(0, tab), _item(1, tab)])),
                // Keeps the notch clear of the centered FAB.
                const SizedBox(width: 64),
                Expanded(child: Row(children: [_item(2, tab)])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, HomeTab tab) => _NavItem(
    icon: _tabs[i].icon,
    activeIcon: _tabs[i].activeIcon,
    label: _tabs[i].label,
    selected: tab.index == i,
    onTap: () => ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.accent : kFgMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkResponse(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          radius: 42,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, size: kBottomNavIconSize, color: color),
              const SizedBox(height: kBottomNavIconLabelGap),
              Text(label, style: kBottomNavLabelStyle.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
