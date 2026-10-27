import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/health_sync.dart';
import '../../state/me.dart';
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
  @override
  void initState() {
    super.initState();
    // Reading the provider is what starts Health sync and its lifecycle listener.
    ref.read(healthSyncProvider);
    unawaited(_followDeviceTimezone());
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
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++) ...[
                // Keeps the notch clear of the centered FAB.
                if (i == 2) const SizedBox(width: 64),
                _NavItem(
                  icon: _tabs[i].icon,
                  activeIcon: _tabs[i].activeIcon,
                  label: _tabs[i].label,
                  selected: tab.index == i,
                  onTap: () => ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
