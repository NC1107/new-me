import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reminders/reminder_plan.dart';
import '../../state/reminders.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/time_presets.dart';

/// The evening reminder: on or off, and at what time.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref, int minutes) async {
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
    final settings = ref.watch(remindersProvider);
    final controller = ref.read(remindersProvider.notifier);
    final custom = !kReminderPresetMinutes.contains(settings.minutes);
    return PageScaffold(
      title: 'Reminders',
      children: [
        Text(
          'One quiet note in the evening if your day has not counted yet. Nothing once it has.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        _SwitchCard(
          on: settings.active,
          onChanged: (on) => on ? controller.enable() : controller.disable(),
        ),
        if (settings.blocked) ...[const SizedBox(height: kCardGap), const _BlockedNote()],
        if (settings.active) ...[
          const SizedBox(height: 24),
          const FieldLabel('What time?'),
          TimePresets(
            selected: settings.minutes,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              controller.setMinutes(value);
            },
          ),
          const SizedBox(height: kCardGap),
          ChunkyButton.secondary(
            label: custom ? formatReminderTime(settings.minutes) : 'Pick another time',
            icon: Icons.schedule_rounded,
            onPressed: () => _pick(context, ref, settings.minutes),
          ),
        ],
      ],
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('amber');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Semantics(
        toggled: on,
        excludeSemantics: true,
        label: 'Evening reminder',
        onTap: () => onChanged(!on),
        child: Pressable(
          scale: 0.99,
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
                    child: Icon(Icons.notifications_rounded, size: 24, color: palette.lip),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Evening reminder',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
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
      ),
    );
  }
}

class _BlockedNote extends StatelessWidget {
  const _BlockedNote();

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.notifications_off_rounded, size: 20, color: kInkSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Notifications are off for New Me. Open the Settings app, tap Notifications, then '
            'New Me, and turn on Allow Notifications.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
