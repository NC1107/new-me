import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/quest_style.dart';
import '../../util/format.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../api/models.dart';
import '../../state/targets.dart';
import '../../state/units.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/skeletons.dart';
import '../../api/daily_reps_models.dart';
import '../../util/reps_exercises.dart';
import '../../widgets/page_scaffold.dart';
import '../log/log_chip.dart';
import '../me/daily_reps_page.dart';
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

/// One daily goal on the targets screen: what it is worth for this person, where the number
/// comes from, and how far a tap moves it.
class PlanGoal {
  const PlanGoal({
    required this.key,
    required this.name,
    required this.value,
    required this.step,
    required this.why,
    required this.label,
    this.min = 1,
    this.extra = const [],
  });

  /// A quest key, or `calories` for the food target.
  final String key;
  final String name;
  final int value;
  final int step;
  final int min;

  /// One line naming where the number comes from, with its short citation, or saying there is
  /// no research figure.
  final String why;
  final String Function(int value) label;

  /// More lines under [why], such as what one serving of fruit and vegetables looks like.
  final List<String> extra;

  PlanGoal withValue(int v) => PlanGoal(
    key: key,
    name: name,
    value: v,
    step: step,
    why: why,
    label: label,
    min: min,
    extra: extra,
  );
}

int? _value(TargetsReport? report, String key) => report?.target(key)?.value;

/// The daily goals for the chosen focuses. A goal with a published figure leads with the
/// recommendation the server worked out from the answers so far; one without says so.
List<PlanGoal> planGoals(
  List<String> questKeys,
  bool wantsFood,
  TargetsReport? report, {
  Units units = Units.metric,
}) {
  PlanGoal goal(String key, String name, int fallback, int step, {int min = 1}) {
    final spec = kGoalSpecs[key];
    final target = spec?.targetKey == null ? null : report?.target(spec!.targetKey!);
    final recommended = target?.value;
    final why = switch (target) {
      final t? when recommended != null && t.why.isNotEmpty =>
        t.cite.isEmpty ? t.why : '${t.why} (${t.cite})',
      _ when spec?.noResearch != null => spec!.noResearch!,
      _ when spec?.targetKey != null => 'A starting point. Add what is missing in Me > Targets.',
      _ => 'A starting point. Change it any time in Me.',
    };
    final examples = target?.details['servingExamples'];
    return PlanGoal(
      key: key,
      name: name,
      value: recommended ?? fallback,
      step: step,
      min: min,
      why: why,
      label: (v) => spec?.describe(v, units) ?? '$v',
      extra: [
        if (recommended != null && examples is List && examples.isNotEmpty)
          'One serving is $kProduceServingGrams g: ${examples.whereType<String>().join(', ')}.',
      ],
    );
  }

  return [
    for (final k in questKeys)
      switch (k) {
        'steps' => goal(k, 'Steps', 7000, 500),
        'exercise' => goal(k, 'Exercise', 22, 5),
        'pushups' => goal(k, 'Push-ups, or a strength workout', 20, 5),
        'reading' => goal(k, 'Reading', 20, 5),
        'meals_logged' => goal(k, 'Meals logged', 3, 1),
        'protein' => goal(k, 'Protein', 100, 5),
        'sleep' => goal(k, 'Sleep', 450, 15),
        'water' => goal(k, 'Water', 2200, 250),
        'sleep_regularity' => goal(k, 'Steady bedtime', 45, 15, min: 15),
        'produce' => goal(k, 'Fruit and vegetables', 5, 1),
        'breathing' => goal(k, 'Breathing', 5, 1),
        'yoga' => goal(k, 'Stretching', 15, 5),
        _ => goal(k, k, kGoalSpecs[k]?.defaultValue ?? 1, 1),
      },
    if (wantsFood && _value(report, 'calories') != null)
      PlanGoal(
        key: 'calories',
        name: 'Calories',
        value: _value(report, 'calories')!,
        step: 50,
        min: 1000,
        why: 'Mifflin-St Jeor resting energy, your activity and your weight goal.',
        label: (v) => '${v.formatted} kcal',
      ),
  ];
}

/// "Your daily goals": one row per chosen focus, worked out from the answers so far, each with
/// where its number comes from and a minus and plus to change it.
class TargetsStep extends ConsumerStatefulWidget {
  const TargetsStep({super.key});

  @override
  ConsumerState<TargetsStep> createState() => _TargetsStepState();
}

class _TargetsStepState extends ConsumerState<TargetsStep> {
  List<PlanGoal>? _goals;

  @override
  void initState() {
    super.initState();
    // The answers on the screens before change the formulas, so read them fresh.
    Future.microtask(() async {
      try {
        await ref.read(targetsProvider.notifier).refresh();
      } on Object catch (e) {
        debugPrint('[NEWME] onboarding targets unavailable: $e');
      }
      if (!mounted) return;
      final s = ref.read(onboardingProvider);
      setState(
        () => _goals = planGoals(
          s.questKeys,
          s.wantsFood,
          ref.read(targetsProvider).value?.data,
          units: s.units ?? ref.read(unitsProvider),
        ),
      );
    });
  }

  Future<void> _chooseReps(int i) async {
    final saved = await pushPage<DailyReps>(context, const DailyRepsPage());
    if (saved == null || !mounted) return;
    final exercise = saved.exercise;
    setState(
      () => _goals![i] = PlanGoal(
        key: 'pushups',
        name: repsTitle(exercise),
        value: saved.target,
        step: saved.sets,
        min: saved.sets,
        why: '${saved.sets} sets sized from your own max.',
        label: (v) => '$v ${repsNoun(exercise, v)}',
      ),
    );
  }

  void _change(int i, int by) {
    final g = _goals![i];
    final next = (g.value + by * g.step).clamp(g.min, 100000);
    HapticFeedback.selectionClick();
    setState(() => _goals![i] = g.withValue(next));
  }

  Future<void> _use() async {
    final goals = _goals!;
    final c = ref.read(onboardingProvider.notifier);
    final report = ref.read(targetsProvider).value?.data;
    await c.commitTargets({
      for (final g in goals)
        if (g.key != 'calories') g.key: g.value,
    }, kcal: goals.where((g) => g.key == 'calories').firstOrNull?.value);
    // Eating well also sets the fat and carb split worked out with the calories.
    if (ref.read(onboardingProvider).wantsFood && report != null) {
      final macros = [
        for (final key in const ['fat', 'carbs'])
          if (report.target(key)?.canUse ?? false) key,
      ];
      if (macros.isNotEmpty) {
        try {
          await ref.read(targetsProvider.notifier).apply(macros);
        } on Object catch (e) {
          debugPrint('[NEWME] macro targets not applied: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(onboardingProvider);
    final goals = _goals;
    return StepLayout(
      footer: [
        ChunkyButton(label: 'Use these', busy: s.busy, onPressed: goals == null ? null : _use),
      ],
      children: [
        const MascotLine(line: 'Worked out from your answers.', state: MascotState.cheer),
        const StepTitle(
          'Your daily goals',
          subtitle: 'From published guidelines where one applies. Change any of them here or later in Me.',
        ),
        if (goals == null)
          const SkeletonBlock(height: 200, radius: 16)
        else ...[
          for (final (i, g) in goals.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            _GoalRow(
              goal: g,
              onLess: () => _change(i, -1),
              onMore: () => _change(i, 1),
              onChoose: g.key == 'pushups' ? () => _chooseReps(i) : null,
            ),
          ],
          if (s.wantsFood && !goals.any((g) => g.key == 'calories')) ...[
            const SizedBox(height: 10),
            AppCard(
              color: kSunken,
              child: Text(
                'Calories are worked out once Apple Health has about five days of steps, from '
                'your resting energy and how active you are. They appear in Me > Targets.',
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
            ),
          ],
        ],
        if (s.error != null) StepError(s.error!),
        const SizedBox(height: 12),
        const Text('General guidance, not medical advice.', style: AppText.caption),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.onLess, required this.onMore, this.onChoose});

  /// Opens the daily-reps setup, for the push-ups goal only.
  final VoidCallback? onChoose;

  final PlanGoal goal;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(goal.name, style: AppText.caption.copyWith(color: kInkMuted)),
              Text(goal.label(goal.value), style: AppText.tabular(AppText.headline)),
              const SizedBox(height: 2),
              Text(goal.why, style: AppText.caption.copyWith(color: kInkSecondary)),
              for (final line in goal.extra)
                Text(line, style: AppText.caption.copyWith(color: kInkSecondary)),
              if (onChoose != null) ...[
                const SizedBox(height: 6),
                LogChip(label: 'Pick an exercise and test your max', onTap: onChoose!),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        ChunkyIconButton(
          icon: Icons.remove_rounded,
          semanticLabel: 'Less ${goal.name}',
          size: 40,
          kind: ChunkyKind.secondary,
          onPressed: goal.value - goal.step >= goal.min ? onLess : null,
        ),
        const SizedBox(width: 6),
        ChunkyIconButton(
          icon: Icons.add_rounded,
          semanticLabel: 'More ${goal.name}',
          size: 40,
          onPressed: onMore,
        ),
      ],
    ),
  );
}

/// Pounds and feet, or kilograms and centimetres, chosen before anything is measured.
class UnitsStep extends ConsumerWidget {
  const UnitsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(onboardingProvider);
    final c = ref.read(onboardingProvider.notifier);
    final selected = s.units ?? ref.watch(unitsProvider);
    return StepLayout(
      footer: [ChunkyButton(label: 'Continue', busy: s.busy, onPressed: c.continueUnits)],
      children: [
        const MascotLine(line: 'Whatever you think in.', state: MascotState.happy),
        const StepTitle(
          'Which units do you use?',
          subtitle: 'You can change this later in Me > Profile.',
        ),
        for (final (i, (u, title, sub)) in const [
          (Units.imperial, 'Pounds and feet', 'lb, ft and in, miles'),
          (Units.metric, 'Kilograms and centimetres', 'kg, cm, kilometres'),
        ].indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ChoiceCard(
            icon: u.isImperial ? Icons.straighten_rounded : Icons.square_foot_rounded,
            title: title,
            subtitle: sub,
            selected: selected == u,
            onTap: () => c.chooseUnits(u),
          ),
        ],
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}
