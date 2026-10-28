import '../../util/errors.dart';
import '../../widgets/app_switch.dart';

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
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/time_presets.dart';

/// How many push switches the page has.
const kNotificationSwitches = 11;

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
  p.milestones,
  p.lookback,
].where((on) => on).length;

/// Which events may notify this phone, and the evening reminder with its time.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, NotificationPatch patch) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setNotificationPref(ref, patch);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save that')));
    }
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: 'Remind me at',
    );
    if (picked == null) return;
    await ref.read(remindersProvider.notifier).setMinutes(picked.hour * 60 + picked.minute);
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
      (
        icon: Icons.calendar_month_rounded,
        palette: accentById('violet'),
        title: 'Monthly look-back',
        subtitle: 'On the 1st, last month against the one before',
        on: prefs.lookback,
        patch: (bool v) => NotificationPatch(lookback: v),
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
      (
        icon: Icons.emoji_events_rounded,
        palette: accentById('amber'),
        title: 'Milestones',
        subtitle: 'Streak lengths and firsts, yours and together',
        on: prefs.milestones,
        patch: (bool v) => NotificationPatch(milestones: v),
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
        Semantics(header: true, child: const Text('Reminders', style: AppText.headline)),
        const SizedBox(height: 4),
        Text(
          'One quiet note in the evening if your day has not counted yet. Nothing once it has.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: _SwitchRow(
            icon: Icons.notifications_rounded,
            palette: accentById('amber'),
            title: 'Evening reminder',
            subtitle: reminders.active ? formatReminderTime(reminders.minutes) : 'Off',
            on: reminders.active,
            onChanged: (on) => on
                ? ref.read(remindersProvider.notifier).enable()
                : ref.read(remindersProvider.notifier).disable(),
          ),
        ),
        if (reminders.active) ...[
          const SizedBox(height: 16),
          const FieldLabel('What time?'),
          TimePresets(
            selected: reminders.minutes,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              ref.read(remindersProvider.notifier).setMinutes(value);
            },
          ),
          const SizedBox(height: kCardGap),
          ChunkyButton.secondary(
            label: kReminderPresetMinutes.contains(reminders.minutes)
                ? 'Pick another time'
                : formatReminderTime(reminders.minutes),
            icon: Icons.schedule_rounded,
            onPressed: () => _pickTime(context, ref, reminders.minutes),
          ),
        ],
        const SizedBox(height: 24),
        Semantics(header: true, child: const Text('Together', style: AppText.headline)),
        const SizedBox(height: 12),
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
                child: AppSwitch(value: on, onChanged: onChanged),
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
