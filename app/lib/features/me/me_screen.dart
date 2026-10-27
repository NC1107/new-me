import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/me.dart';
import '../../state/reminders.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../reminders/reminder_plan.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import 'apple_health_page.dart';
import 'audiobookshelf_page.dart';
import 'daily_goals_page.dart';
import 'food_targets_page.dart';
import 'pairing_page.dart';
import 'profile_page.dart';
import 'reminders_page.dart';
import 'settings_row.dart';
import 'timezone_page.dart';

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
    final reminders = ref.watch(remindersProvider);
    final now = ref.watch(clockProvider)();
    final enabled = me.questTemplates.where((q) => q.enabled).length;
    final kcal = me.targets.kcal;
    final accent = accentById(me.user.color);
    final synced = health.lastSyncedAt;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 96),
      children: [
        _Header(me: me),
        const SizedBox(height: 24),
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
              icon: Icons.restaurant_rounded,
              palette: accentById('green'),
              title: 'Food targets',
              subtitle: kcal == null ? 'Not set' : '${kcal.formatted} kcal a day',
              onTap: () => pushPage(context, const FoodTargetsPage()),
            ),
            SettingsRow(
              icon: Icons.palette_rounded,
              palette: accent,
              title: 'Profile',
              subtitle: '${me.user.name}, ${accent.name}',
              onTap: () => pushPage(context, const ProfilePage()),
            ),
            SettingsRow(
              icon: Icons.public_rounded,
              palette: accentById('sky'),
              title: 'Time zone',
              subtitle: me.user.timezone,
              onTap: () => pushPage(context, const TimezonePage()),
            ),
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
            SettingsRow(
              icon: Icons.notifications_rounded,
              palette: accentById('amber'),
              title: 'Reminders',
              subtitle: reminders.active ? formatReminderTime(reminders.minutes) : 'Off',
              onTap: () => pushPage(context, const RemindersPage()),
            ),
            if (me.audiobookshelf case final link?)
              SettingsRow(
                icon: Icons.headphones_rounded,
                palette: accentById('violet'),
                title: 'Audiobookshelf',
                subtitle: _audiobookshelfSubtitle(link, now),
                onTap: () => pushPage(context, const AudiobookshelfPage()),
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
        const _LeaveButton(),
        const SizedBox(height: 20),
        const Center(child: Text('New Me $kClientVersion', style: AppText.caption)),
      ],
    );
  }
}

String _audiobookshelfSubtitle(AudiobookshelfLink link, DateTime now) {
  if (!link.linked) return 'Count audiobook listening';
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
                        text: mine.streak < 1 ? 'No streak yet' : '${mine.streak} day streak',
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

class _LeaveButton extends ConsumerWidget {
  const _LeaveButton();

  static final _danger = AccentPalette.of('danger', 'Danger', 0xFFD9534F, 0xFFB23C38, 0xFFFCE9E7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(meProvider.select((m) => m.value?.data.user.isAdmin)) ?? false;
    return ChunkyButton.secondary(
      label: 'Leave this phone',
      palette: _danger,
      onPressed: () async {
        final confirmed = await confirmDialog(
          context,
          title: 'Leave this phone?',
          message: isAdmin
              ? 'This phone is signed out. You are the admin, so a new pairing code can only come '
                    'from the server itself.'
              : 'This phone is signed out. Your scores stay on the server and a new pairing '
                    'code brings you back.',
          confirmLabel: 'Leave',
          destructive: true,
        );
        if (!confirmed) return;
        HapticFeedback.mediumImpact();
        await ref.read(sessionProvider.notifier).signOut();
      },
    );
  }
}
