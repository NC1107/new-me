import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/quest_style.dart';
import '../../util/format.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/preset_list.dart';
import 'goal_catalog.dart';
import 'onboarding_controller.dart';
import 'step_layout.dart';

class FocusStep extends ConsumerWidget {
  const FocusStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Continue',
          onPressed: state.focuses.isEmpty ? null : controller.continueFocus,
        ),
      ],
      children: [
        MascotLine(
          line: 'Pick as many as you like.',
          state: state.focuses.isEmpty ? MascotState.idle : MascotState.happy,
        ),
        const StepTitle('What do you want to work on?'),
        for (final (i, focus) in kFocuses.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ChoiceCard(
            icon: focus.icon,
            title: focus.title,
            subtitle: focus.subtitle,
            iconPalette: questPalette(focus.colorKey),
            selected: state.focuses.contains(focus.id),
            showCheck: true,
            onTap: () => controller.toggleFocus(focus.id),
          ),
        ],
      ],
    );
  }
}

class GoalStep extends ConsumerWidget {
  const GoalStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final keys = state.questKeys;
    if (state.goalIndex >= keys.length) return const SizedBox.shrink();
    final key = keys[state.goalIndex];
    final spec = kGoalSpecs[key]!;
    return StepLayout(
      footer: [
        ChunkyButton(label: 'Continue', busy: state.busy, onPressed: controller.continueGoal),
      ],
      children: [
        const MascotLine(line: 'Change it any time.'),
        StepTitle(spec.question, subtitle: spec.note),
        PresetList<int>(
          presets: [
            for (final o in spec.options)
              Preset(name: o.name, valueLabel: spec.label(o.value), value: o.value),
          ],
          selected: state.selectedGoal(key),
          onChanged: (v) => controller.setGoal(key, v),
        ),
        if (state.error != null) StepError(state.error!),
      ],
    );
  }
}

class FoodStep extends ConsumerWidget {
  const FoodStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Continue',
          busy: state.busy,
          onPressed: state.kcal == null ? null : controller.continueFood,
        ),
        ChunkyButton.secondary(label: 'Skip', onPressed: state.busy ? null : controller.skipFood),
      ],
      children: [
        const MascotLine(line: 'Totally optional.', state: MascotState.thinking),
        const StepTitle(
          'Want a daily calorie target?',
          subtitle: 'It shows on your food card. Skip it if you like.',
        ),
        PresetList<int>(
          presets: [
            for (final o in kCalorieOptions)
              Preset(name: o.name, valueLabel: '${o.value.formatted} kcal', value: o.value),
          ],
          selected: state.kcal,
          onChanged: controller.setKcal,
        ),
        if (state.error != null) StepError(state.error!),
      ],
    );
  }
}
