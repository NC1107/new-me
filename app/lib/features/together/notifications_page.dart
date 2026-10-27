import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../reminders/reminder_plan.dart';
import '../../state/me.dart';
import '../../state/reminders.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../me/reminders_page.dart';
import '../me/settings_row.dart';

/// How many push switches the page has.
const kNotificationSwitches = 9;

/// How many of the push switches are on, for the Me row's subtitle.
int notificationsOn(NotificationPrefs p) => [
  p.partnerDone,
  p.cheers,
  p.challenge,
  p.reward,
  p.behindPace,
  p.closeToDone,
  p.windDown,
  p.morningPlan,
  p.weeklyRecap,
].where((on) => on).length;

/// Which events may notify this phone, plus a way into the evening reminder.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, NotificationPatch patch) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setNotificationPref(ref, patch);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save that')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(
      meProvider.select((m) => m.value?.data.notifications ?? const NotificationPrefs()),
    );
    final reminders = ref.watch(remindersProvider);
    final nudges = [
      (
        icon: Icons.directions_walk_rounded,
        palette: accentById('sky'),
        title: 'Steps to go',
        subtitle: 'A nudge when a walk would close your steps',
        on: prefs.behindPace,
        patch: (bool v) => NotificationPatch(behindPace: v),
      ),
      (
        icon: Icons.flag_circle_rounded,
        palette: accentById('green'),
        title: 'Close to done',
        subtitle: 'When one quest is all that is left to count your day',
        on: prefs.closeToDone,
        patch: (bool v) => NotificationPatch(closeToDone: v),
      ),
      (
        icon: Icons.bedtime_rounded,
        palette: accentById('violet'),
        title: 'Wind down',
        subtitle: 'A heads up before the bedtime your sleep goal needs',
        on: prefs.windDown,
        patch: (bool v) => NotificationPatch(windDown: v),
      ),
      (
        icon: Icons.wb_sunny_rounded,
        palette: accentById('amber'),
        title: 'Morning plan',
        subtitle: 'How ready you are and what today holds',
        on: prefs.morningPlan,
        patch: (bool v) => NotificationPatch(morningPlan: v),
      ),
      (
        icon: Icons.insights_rounded,
        palette: accentById('teal'),
        title: 'Weekly recap',
        subtitle: 'Sunday evening, your week against the last',
        on: prefs.weeklyRecap,
        patch: (bool v) => NotificationPatch(weeklyRecap: v),
      ),
    ];
    final rows = [
      (
        icon: Icons.check_circle_rounded,
        palette: accentById('green'),
        title: 'Partner finished their day',
        subtitle: 'When their day counts',
        on: prefs.partnerDone,
        patch: (bool v) => NotificationPatch(partnerDone: v),
      ),
      (
        icon: Icons.celebration_rounded,
        palette: accentById('amber'),
        title: 'Cheers',
        subtitle: 'When they cheer your day',
        on: prefs.cheers,
        patch: (bool v) => NotificationPatch(cheers: v),
      ),
      (
        icon: Icons.flag_rounded,
        palette: accentById('sky'),
        title: 'Weekly challenge',
        subtitle: 'When you complete it together',
        on: prefs.challenge,
        patch: (bool v) => NotificationPatch(challenge: v),
      ),
      (
        icon: Icons.card_giftcard_rounded,
        palette: accentById('rose'),
        title: 'Shared reward',
        subtitle: 'When you earn it',
        on: prefs.reward,
        patch: (bool v) => NotificationPatch(reward: v),
      ),
    ];
    return PageScaffold(
      title: 'Notifications',
      children: [
        Text(
          'Pick what is worth a buzz. Points and challenges count either way.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (reminders.loaded && !reminders.allowed) ...[
          _PermissionCard(
            asked: reminders.enabled,
            onAllow: () => ref.read(remindersProvider.notifier).requestPermission(),
          ),
          const SizedBox(height: kCardGap),
        ],
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                _SwitchRow(
                  icon: row.icon,
                  palette: row.palette,
                  title: row.title,
                  subtitle: row.subtitle,
                  on: row.on,
                  onChanged: (v) => _set(context, ref, row.patch(v)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Semantics(header: true, child: const Text('Nudges and plan', style: AppText.headline)),
        const SizedBox(height: 4),
        Text(
          'At most two of these a day, and none late at night.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, row) in nudges.indexed) ...[
                if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                _SwitchRow(
                  icon: row.icon,
                  palette: row.palette,
                  title: row.title,
                  subtitle: row.subtitle,
                  on: row.on,
                  onChanged: (v) => _set(context, ref, row.patch(v)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.notifications_rounded,
              palette: accentById('amber'),
              title: 'Evening reminder',
              subtitle: reminders.active ? formatReminderTime(reminders.minutes) : 'Off',
              onTap: () => pushPage(context, const RemindersPage()),
            ),
          ],
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onChanged,
  });

  final IconData icon;
  final AccentPalette palette;
  final String title;
  final String subtitle;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: on,
    excludeSemantics: true,
    label: '$title, $subtitle',
    onTap: () => onChanged(!on),
    child: Pressable(
      scale: 0.99,
      haptic: false,
      onTap: () => onChanged(!on),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(icon, size: 24, color: palette.lip),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    Text(subtitle, style: AppText.caption.copyWith(color: kInkSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                child: Switch(
                  value: on,
                  onChanged: onChanged,
                  activeThumbColor: kSurface,
                  activeTrackColor: context.accent,
                  inactiveThumbColor: kSurface,
                  inactiveTrackColor: kLip,
                  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shown while iOS has not allowed notifications: without it none of the switches can deliver.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.asked, required this.onAllow});

  final bool asked;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.notifications_off_rounded, size: 20, color: kInkSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                asked
                    ? 'Notifications are off for New Me. Open the Settings app, tap Notifications, '
                          'then New Me, and turn on Allow Notifications.'
                    : 'New Me cannot notify you yet. Allow notifications to hear when your '
                          'partner cheers or finishes their day.',
                style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          container: true,
          child: ChunkyButton(
            label: 'Allow notifications',
            icon: Icons.notifications_active_rounded,
            onPressed: onAllow,
          ),
        ),
      ],
    ),
  );
}
