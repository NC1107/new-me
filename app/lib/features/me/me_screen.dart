import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../state/habits.dart';
import '../../state/health_sync.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../reminders/reminder_plan.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../habits/habits_page.dart';
import '../insights/insights_screen.dart';
import 'apple_health_page.dart';
import 'audiobookshelf_page.dart';
import 'daily_goals_page.dart';
import '../streaks/away_page.dart';
import 'pairing_page.dart';
import 'profile_page.dart';
import 'schedule_page.dart';
import '../together/notifications_page.dart';
import 'settings_row.dart';
import 'targets_page.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: CachedView<Me>(
        value: ref.watch(meProvider),
        skeleton: const MeSkeleton(),
        errorTitle: 'Could not load your profile',
        onRetry: ref.read(meProvider.notifier).refresh,
        builder: (context, me, offline) => RefreshIndicator(
          color: context.accent,
          backgroundColor: kSurface,
          onRefresh: ref.read(meProvider.notifier).refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: _MeBody(me: me),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeBody extends ConsumerWidget {
  const _MeBody({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthSyncProvider);
    final habitCount = ref.watch(habitsProvider.select((h) => h.value?.data.habits.length));
    final now = ref.watch(clockProvider)();
    final enabled = me.questTemplates.where((q) => q.enabled).length;
    final away = ref.watch(todayProvider.select((t) => t.value?.data.away)) ?? const AwayState();
    final accent = accentById(me.user.color);
    final synced = health.lastSyncedAt;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 96),
      children: [
        Semantics(header: true, child: const Text('Me', style: AppText.display)),
        const SizedBox(height: 16),
        _Header(me: me),
        Semantics(header: true, child: const SectionLabel('Plan')),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.flag_rounded,
              palette: accentById('amber'),
              title: 'Daily goals',
              subtitle: '$enabled of ${me.questTemplates.length} on',
              onTap: () => pushPage(context, const DailyGoalsPage()),
            ),
            SettingsRow(
              icon: Icons.checklist_rounded,
              palette: accentById('teal'),
              title: 'Habits',
              subtitle: habitCount == null
                  ? 'Daily routines'
                  : habitCount == 1
                  ? '1 habit'
                  : '$habitCount habits',
              onTap: () => pushPage(context, const HabitsPage()),
            ),
            SettingsRow(
              icon: Icons.science_rounded,
              palette: accentById('green'),
              title: 'Targets',
              subtitle: 'Calories, macros, sleep and more, with sources',
              onTap: () => pushPage(context, const TargetsPage()),
            ),
            SettingsRow(
              icon: Icons.insights_rounded,
              palette: accentById('sky'),
              title: 'Insights',
              subtitle: 'Steps, sleep and workouts',
              onTap: () => openInsights(context),
            ),
          ],
        ),
        Semantics(header: true, child: const SectionLabel('You')),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.person_rounded,
              palette: accent,
              title: 'About you',
              subtitle: '${me.user.name}, units and body',
              onTap: () => pushPage(context, const ProfilePage()),
            ),
            SettingsRow(
              icon: Icons.schedule_rounded,
              palette: accentById('amber'),
              title: 'Schedule',
              subtitle: scheduleSummary(me.schedule),
              onTap: () => pushPage(context, const SchedulePage()),
            ),
            SettingsRow(
              icon: Icons.pause_circle_rounded,
              palette: accentById('sky'),
              title: 'Away days',
              subtitle: awaySummary(away),
              onTap: () => pushPage(context, const AwayPage()),
            ),
          ],
        ),
        Semantics(header: true, child: const SectionLabel('Connections')),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.favorite_rounded,
              palette: accentById('rose'),
              title: 'Apple Health',
              subtitle: !health.prompted
                  ? 'Not connected'
                  : synced == null
                  ? 'Connected, not synced yet'
                  : 'Last sync ${relativeTime(synced, now)}',
              onTap: () => pushPage(context, const AppleHealthPage()),
            ),
            if (me.audiobookshelf case final link?)
              SettingsRow(
                icon: Icons.headphones_rounded,
                palette: accentById('violet'),
                title: 'Audiobookshelf',
                subtitle: _audiobookshelfSubtitle(link, now),
                onTap: () => pushPage(context, const AudiobookshelfPage()),
              ),
          ],
        ),
        Semantics(header: true, child: const SectionLabel('App')),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.notifications_active_rounded,
              palette: accentById('rose'),
              title: 'Notifications',
              subtitle: '${notificationsOn(me.notifications)} of $kNotificationSwitches on',
              onTap: () => pushPage(context, const NotificationsPage()),
            ),
            if (me.user.isAdmin)
              SettingsRow(
                icon: Icons.group_add_rounded,
                palette: accentById('teal'),
                title: 'Pairing code',
                subtitle: 'Invite your partner',
                onTap: () => pushPage(context, const PairingPage()),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const _SignOutButton(),
        const SizedBox(height: 20),
        const Center(child: Text('New Me $kClientVersion', style: AppText.caption)),
      ],
    );
  }
}

/// "Mon to Fri, up at 7:00 AM" for the Me row.
String scheduleSummary(Schedule s) =>
    '${workdaysLabel(s.workdays)}, up at ${formatReminderTime(s.workday.wake)}';

/// What the Away row says: where the person is away now, what is coming, or what it is for.
String awaySummary(AwayState away) {
  final span = away.current;
  if (span != null) return 'Away until ${awayRangeLabel(span.to, span.to)}';
  if (away.upcoming.isNotEmpty) {
    return 'Next: ${awayRangeLabel(away.upcoming.first.from, away.upcoming.first.to)}';
  }
  return 'Pause streaks when sick or traveling';
}

String _audiobookshelfSubtitle(AudiobookshelfLink link, DateTime now) {
  if (!link.linked) return 'Not linked';
  final name = link.username ?? 'Linked';
  if (link.needsSignIn) return '$name, sign in again';
  final synced = link.syncedAt;
  return synced == null ? name : '$name, synced ${relativeTime(synced, now)}';
}

class _Header extends ConsumerWidget {
  const _Header({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = accentById(me.user.color);
    final users = ref.watch(boardProvider).value?.data.users ?? const <BoardUser>[];
    final mine = users.where((u) => u.id == me.user.id).firstOrNull;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Avatar(name: me.user.name, palette: accent, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title,
                ),
                if (mine != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _Stat(
                        icon: Icons.local_fire_department_rounded,
                        color: kFlame,
                        text: mine.streak < 1
                            ? 'Start a streak today'
                            : '${mine.streak} day streak',
                      ),
                      _Stat(
                        icon: Icons.diamond_rounded,
                        color: accentById('sky').fill,
                        text: '${mine.season.formatted} season points',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(text, style: AppText.label.copyWith(color: kInkSecondary)),
      ),
    ],
  );
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  static final _danger = AccentPalette.of('danger', 'Danger', 0xFFD9534F, 0xFFB23C38, 0xFFFCE9E7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(meProvider.select((m) => m.value?.data.user.isAdmin)) ?? false;
    return ChunkyButton.secondary(
      label: 'Sign out of this phone',
      palette: _danger,
      onPressed: () async {
        final confirmed = await confirmDialog(
          context,
          title: 'Sign out of this phone?',
          message: isAdmin
              ? 'This phone is signed out. You are the admin, so a new pairing code can only come '
                    'from the server itself.'
              : 'This phone is signed out. Your scores stay on the server and a new pairing '
                    'code brings you back.',
          confirmLabel: 'Sign out',
          destructive: true,
        );
        if (!confirmed) return;
        HapticFeedback.mediumImpact();
        await ref.read(sessionProvider.notifier).signOut();
      },
    );
  }
}
