import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/confetti.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pop_in.dart';
import '../../widgets/time_presets.dart';
import 'onboarding_controller.dart';
import 'step_layout.dart';

class _HealthGroup {
  const _HealthGroup(this.icon, this.title, this.detail, this.paletteId);

  final IconData icon;
  final String title;
  final String detail;
  final String paletteId;
}

const _groups = [
  _HealthGroup(
    Icons.directions_run_rounded,
    'Activity',
    'Steps, distance, flights, active energy',
    'sky',
  ),
  _HealthGroup(Icons.fitness_center_rounded, 'Workouts', 'Workouts and exercise minutes', 'rose'),
  _HealthGroup(Icons.bedtime_rounded, 'Sleep', 'Time asleep each night', 'violet'),
  _HealthGroup(Icons.favorite_rounded, 'Heart', 'Resting heart rate, HRV, VO2 max', 'amber'),
  _HealthGroup(Icons.monitor_weight_rounded, 'Body', 'Weight, height, body fat, lean mass', 'teal'),
  _HealthGroup(Icons.spa_rounded, 'Mindfulness and water', 'Mindful minutes, water', 'green'),
];

class HealthStep extends ConsumerWidget {
  const HealthStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(onboardingProvider.select((s) => s.busy));
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Connect Apple Health',
          icon: Icons.favorite_rounded,
          busy: busy,
          onPressed: controller.connectHealth,
        ),
        ChunkyButton.secondary(label: 'Not now', onPressed: busy ? null : controller.skipHealth),
      ],
      children: [
        const MascotLine(line: 'I only read, I never write.', state: MascotState.happy),
        const StepTitle(
          'Connect Apple Health',
          subtitle: 'New Me reads these so your days count on their own.',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final (i, g) in _groups.indexed) ...[
                if (i > 0) const Divider(height: 1, thickness: 2, color: kSunken),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accentById(g.paletteId).tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(g.icon, size: 22, color: accentById(g.paletteId).lip),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.title, style: AppText.label.copyWith(fontSize: 15)),
                            Text(g.detail, style: AppText.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 16, color: kInkMuted),
            SizedBox(width: 6),
            Flexible(child: Text('New Me never writes to Health.', style: AppText.caption)),
          ],
        ),
      ],
    );
  }
}

class ReminderStep extends ConsumerWidget {
  const ReminderStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(onboardingProvider.select((s) => s.busy));
    final minutes = ref.watch(onboardingProvider.select((s) => s.reminderMinutes));
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Allow',
          icon: Icons.notifications_active_rounded,
          busy: busy,
          onPressed: controller.allowReminders,
        ),
        ChunkyButton.secondary(label: 'Not now', onPressed: busy ? null : controller.skipReminders),
      ],
      children: [
        const MascotLine(line: 'Want a nudge in the evening?', state: MascotState.happy),
        const StepTitle(
          'Evening reminder',
          subtitle: 'One quiet note a day if your day has not counted yet. Nothing once it has.',
        ),
        const FieldLabel('What time?'),
        TimePresets(selected: minutes, onChanged: controller.setReminderMinutes),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune_rounded, size: 16, color: kInkMuted),
            SizedBox(width: 6),
            Flexible(child: Text('You can change this any time in Me.', style: AppText.caption)),
          ],
        ),
      ],
    );
  }
}

class DoneStep extends ConsumerStatefulWidget {
  const DoneStep({super.key});

  @override
  ConsumerState<DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends ConsumerState<DoneStep> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final name = state.displayName;
    final returning = state.path == OnboardingPath.returning;
    final palette = accentById(state.color);
    return Stack(
      children: [
        Positioned.fill(
          child: StepLayout(
            footer: [
              ChunkyButton(
                label: "Let's go",
                onPressed: ref.read(onboardingProvider.notifier).finish,
              ),
            ],
            children: [
              const SizedBox(height: 48),
              Center(
                child: Mascot(size: 176, state: MascotState.cheer, palette: palette),
              ),
              const SizedBox(height: 28),
              PopIn(
                delay: const Duration(milliseconds: 150),
                child: Text(
                  returning ? 'Welcome back, $name!' : "You're in, $name!",
                  textAlign: TextAlign.center,
                  style: AppText.display,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                returning ? 'Your streak is waiting.' : 'Day 1 starts now.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(fontSize: 18, color: kInkSecondary),
              ),
            ],
          ),
        ),
        const Positioned.fill(child: Confetti(origin: Alignment(0, -0.35))),
      ],
    );
  }
}
