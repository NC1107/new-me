import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../reminders/reminder_plan.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/time_presets.dart';
import 'onboarding_controller.dart';
import 'step_layout.dart';

const kWakePresets = [6 * 60, 7 * 60, 8 * 60];
const kBedPresets = [22 * 60, 23 * 60, 0];

/// "When do you usually wake up?": one screen for wake and bed time. Reminders, nudges and quiet
/// hours follow it, and Me > Schedule fine-tunes workdays and days off later.
class ScheduleStep extends ConsumerWidget {
  const ScheduleStep({super.key});

  Future<void> _pick(BuildContext context, int initial, String help, ValueChanged<int> set) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      helpText: help,
    );
    if (picked != null) set(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(onboardingProvider);
    final c = ref.read(onboardingProvider.notifier);
    final sameTime = s.wakeMinutes == s.bedMinutes;
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Continue',
          busy: s.busy,
          onPressed: sameTime ? null : c.continueSchedule,
        ),
        ChunkyButton.secondary(
          label: 'Use ${formatReminderTime(kDefaultWake)} and ${formatReminderTime(kDefaultBed)}',
          onPressed: s.busy ? null : c.skipSchedule,
        ),
      ],
      children: [
        const MascotLine(line: 'Let me keep the mornings quiet.', state: MascotState.sleepy),
        const StepTitle(
          'When do you usually wake up?',
          subtitle: 'Notes start a little after you are up and stop at bedtime.',
        ),
        const FieldLabel('Wake up'),
        TimePresets(selected: s.wakeMinutes, minutes: kWakePresets, onChanged: c.setWake),
        const SizedBox(height: kCardGap),
        ChunkyButton.secondary(
          label: kWakePresets.contains(s.wakeMinutes)
              ? 'Pick another time'
              : formatReminderTime(s.wakeMinutes),
          icon: Icons.schedule_rounded,
          onPressed: () => _pick(context, s.wakeMinutes, 'I wake up at', c.setWake),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Bedtime'),
        TimePresets(selected: s.bedMinutes, minutes: kBedPresets, onChanged: c.setBed),
        const SizedBox(height: kCardGap),
        ChunkyButton.secondary(
          label: kBedPresets.contains(s.bedMinutes)
              ? 'Pick another time'
              : formatReminderTime(s.bedMinutes),
          icon: Icons.bedtime_rounded,
          onPressed: () => _pick(context, s.bedMinutes, 'I go to bed at', c.setBed),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Your day starts'),
        ChunkyButton.secondary(
          label: formatReminderTime((s.wakeMinutes + s.startOffsetMin) % (24 * 60)),
          icon: Icons.wb_sunny_rounded,
          onPressed: () => _pick(
            context,
            (s.wakeMinutes + s.startOffsetMin) % (24 * 60),
            'My day starts at',
            c.setDayStart,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your first note waits until then, even if you are up earlier.',
          style: AppText.caption,
        ),
        if (sameTime) const StepError('Wake up and bedtime need to be different.'),
        if (s.error != null) StepError(s.error!),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune_rounded, size: 16, color: kInkMuted),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Workdays and days off are set in Me > Schedule.',
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
