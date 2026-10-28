import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/targets.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/skeletons.dart';
import '../insights/birth_year_sheet.dart' show kEarliestBirthYear;
import '../log/log_chip.dart';
import '../me/targets_logic.dart';
import '../onboarding/step_layout.dart';
import 'about_you.dart';
import '../../widgets/height_input.dart';

/// One "About you" screen. [onNext] moves the host (onboarding or the standalone page) on, and
/// is called after a save, a skip or the final choice.
class AboutYouStep extends ConsumerWidget {
  const AboutYouStep({super.key, required this.question, required this.onNext});

  final AboutQuestion question;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(aboutYouProvider.select((s) => s.ready));
    final units = ref.watch(aboutYouProvider.select((s) => s.units));
    if (!ready) return const _Loading();
    return switch (question) {
      AboutQuestion.birthYear => _NumberQuestion(
        question: question,
        onNext: onNext,
        mascot: 'Only for the maths.',
        title: 'What year were you born?',
        why:
            'Used by the Mifflin-St Jeor equation for your resting energy, and for the step and '
            'fiber guides for your age. It is never shown to anyone else.',
        hint: 'For example 1990',
        semanticLabel: 'Birth year',
        digitsOnly: true,
        maxLength: 4,
      ),
      AboutQuestion.sex => _SexQuestion(onNext: onNext),
      AboutQuestion.height => _HeightQuestion(onNext: onNext),
      AboutQuestion.weight => _NumberQuestion(
        question: question,
        onNext: onNext,
        mascot: 'Just a number, no judging.',
        title: 'What do you weigh?',
        why:
            'Used by the Mifflin-St Jeor equation for your resting energy and to set protein for '
            'your weight. A new weigh-in later keeps it current.',
        hint: units.isImperial ? 'For example 160' : 'For example 72.5',
        semanticLabel: units.isImperial ? 'Weight in pounds' : 'Weight in kilograms',
        unit: units.weightUnit,
        maxLength: 6,
      ),
      AboutQuestion.goal => _GoalQuestion(onNext: onNext),
      AboutQuestion.review => _ReviewStep(onNext: onNext),
    };
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const Padding(
      padding: EdgeInsets.fromLTRB(kGutter, 8, kGutter, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBlock(height: 84, radius: 16),
          SizedBox(height: 32),
          SkeletonBlock(height: 28, radius: 8),
          SizedBox(height: kCardGap),
          SkeletonBlock(height: 52, radius: 12),
        ],
      ),
    ),
  );
}

/// The Continue and Skip pair every question but the last carries.
List<Widget> _footer({
  required bool busy,
  required VoidCallback? onContinue,
  required VoidCallback onSkip,
}) => [
  ChunkyButton(label: 'Continue', busy: busy, onPressed: onContinue),
  ChunkyButton.secondary(label: 'Skip', onPressed: busy ? null : onSkip),
];

Future<void> _confirm(WidgetRef ref, AboutQuestion question, VoidCallback onNext) async {
  final ok = await ref.read(aboutYouProvider.notifier).confirm(question);
  if (ok) onNext();
}

class _NumberQuestion extends ConsumerStatefulWidget {
  const _NumberQuestion({
    required this.question,
    required this.onNext,
    required this.mascot,
    required this.title,
    required this.why,
    required this.hint,
    required this.semanticLabel,
    required this.maxLength,
    this.unit,
    this.digitsOnly = false,
  });

  final AboutQuestion question;
  final VoidCallback onNext;
  final String mascot;
  final String title;
  final String why;
  final String hint;
  final String semanticLabel;
  final int maxLength;
  final String? unit;
  final bool digitsOnly;

  @override
  ConsumerState<_NumberQuestion> createState() => _NumberQuestionState();
}

class _NumberQuestionState extends ConsumerState<_NumberQuestion> {
  late final TextEditingController _controller = TextEditingController(text: _stored);

  AboutQuestion get _q => widget.question;

  String get _stored {
    final s = ref.read(aboutYouProvider);
    return _q == AboutQuestion.birthYear ? s.birthYear : s.weight;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String v) {
    final c = ref.read(aboutYouProvider.notifier);
    if (_q == AboutQuestion.birthYear) {
      c.setBirthYear(v);
    } else {
      c.setWeight(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aboutYouProvider);
    final thisYear = ref.watch(clockProvider)().year;
    final bool valid;
    final bool typed;
    final String rangeError;
    final bool fromHealth;
    switch (_q) {
      case AboutQuestion.birthYear:
        final year = s.birthYearValue;
        valid = year != null && year <= thisYear;
        typed = s.birthYear.trim().length == 4;
        rangeError = 'Between $kEarliestBirthYear and $thisYear';
        fromHealth = false;
      default:
        valid = s.weightValid;
        typed = s.weight.trim().isNotEmpty;
        rangeError = weightRangeError(s.units);
        fromHealth = s.weightFromHealth;
    }
    return StepLayout(
      footer: _footer(
        busy: s.busy,
        onContinue: valid ? () => _confirm(ref, _q, widget.onNext) : null,
        onSkip: widget.onNext,
      ),
      children: [
        MascotLine(line: widget.mascot, state: MascotState.thinking),
        StepTitle(widget.title, subtitle: widget.why),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: _controller,
                hint: widget.hint,
                semanticLabel: widget.semanticLabel,
                autofocus: false,
                keyboardType: widget.digitsOnly
                    ? TextInputType.number
                    : const TextInputType.numberWithOptions(decimal: true),
                errorText: typed && !valid ? rangeError : null,
                onChanged: _changed,
                onSubmitted: valid ? (_) => _confirm(ref, _q, widget.onNext) : null,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(widget.maxLength),
                  if (widget.digitsOnly) FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
            if (widget.unit != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(widget.unit!, style: AppText.headline),
              ),
            ],
          ],
        ),
        if (fromHealth) ...[const SizedBox(height: 10), const _FromHealth()],
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}

/// "Between 44 and 882 lb": the weights the server accepts, in the person's units.
String weightRangeError(Units units) =>
    'Between ${units.weightIn(kWeightRange.min).round()} and ${units.weightIn(kWeightRange.max).round()} ${units.weightUnit}';

class _HeightQuestion extends ConsumerWidget {
  const _HeightQuestion({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aboutYouProvider);
    return StepLayout(
      footer: _footer(
        busy: s.busy,
        onContinue: s.heightValid ? () => _confirm(ref, AboutQuestion.height, onNext) : null,
        onSkip: onNext,
      ),
      children: [
        const MascotLine(line: 'Your tallest self, please.', state: MascotState.thinking),
        const StepTitle(
          'How tall are you?',
          subtitle:
              'Used by the Mifflin-St Jeor equation for your resting energy, and to keep protein '
              'in range for your height.',
        ),
        HeightInput(
          units: s.units,
          initialCm: s.heightCm,
          onChanged: (cm, {required valid}) =>
              ref.read(aboutYouProvider.notifier).setHeight(cm, valid: valid),
        ),
        if (s.heightFromHealth) ...[const SizedBox(height: 10), const _FromHealth()],
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}

class _FromHealth extends StatelessWidget {
  const _FromHealth();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.favorite_rounded, size: 16, color: kInkMuted),
      SizedBox(width: 6),
      Flexible(child: Text('From Apple Health', style: AppText.caption)),
    ],
  );
}

/// Birth year, sex, height and weight on one screen, for onboarding: everything the formulas
/// need that a person knows by heart, prefilled from Apple Health where it shared them.
class AboutYouBodyStep extends ConsumerStatefulWidget {
  const AboutYouBodyStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<AboutYouBodyStep> createState() => _AboutYouBodyStepState();
}

class _AboutYouBodyStepState extends ConsumerState<AboutYouBodyStep> {
  late final _year = TextEditingController(text: ref.read(aboutYouProvider).birthYear);
  late final _weight = TextEditingController(text: ref.read(aboutYouProvider).weight);

  @override
  void dispose() {
    _year.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final ok = await ref.read(aboutYouProvider.notifier).confirmBody();
    if (ok) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aboutYouProvider);
    if (!s.ready) return const _Loading();
    final c = ref.read(aboutYouProvider.notifier);
    final thisYear = ref.watch(clockProvider)().year;
    final year = s.birthYearValue;
    final yearTyped = s.birthYear.trim().length == 4;
    final yearOk = s.birthYear.trim().isEmpty || (year != null && year <= thisYear);
    final weightOk = s.weight.trim().isEmpty || s.weightValid;
    final ok = yearOk && weightOk && s.heightTyped;
    return StepLayout(
      footer: [
        ChunkyButton(label: 'Continue', busy: s.busy, onPressed: ok ? _continue : null),
        ChunkyButton.secondary(label: 'Skip for now', onPressed: s.busy ? null : widget.onNext),
      ],
      children: [
        const MascotLine(line: 'Only what you know already.', state: MascotState.thinking),
        const StepTitle(
          'About you',
          subtitle:
              'New Me works out your calories, protein and more from these with published '
              'formulas. Never shown to anyone else.',
        ),
        const FieldLabel('Year you were born'),
        AppTextField(
          controller: _year,
          hint: 'For example 1990',
          semanticLabel: 'Birth year',
          keyboardType: TextInputType.number,
          errorText: yearTyped && !yearOk ? 'Between $kEarliestBirthYear and $thisYear' : null,
          onChanged: c.setBirthYear,
          inputFormatters: [
            LengthLimitingTextInputFormatter(4),
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Sex'),
        Row(
          children: [
            for (final (i, (value, label)) in const [
              ('male', 'Male'),
              ('female', 'Female'),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: LogChip(
                  label: label,
                  selected: s.sex == value,
                  onTap: () => c.setSex(value),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('Height'),
        HeightInput(units: s.units, initialCm: s.heightCm, onChanged: c.setHeight),
        if (s.heightFromHealth) ...[const SizedBox(height: 6), const _FromHealth()],
        const SizedBox(height: 20),
        FieldLabel('Weight in ${s.units.isImperial ? 'pounds' : 'kilograms'}'),
        AppTextField(
          controller: _weight,
          hint: s.units.isImperial ? 'For example 160' : 'For example 72.5',
          semanticLabel: s.units.isImperial ? 'Weight in pounds' : 'Weight in kilograms',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: weightOk ? null : weightRangeError(s.units),
          onChanged: c.setWeight,
          inputFormatters: [LengthLimitingTextInputFormatter(6)],
        ),
        if (s.weightFromHealth) ...[const SizedBox(height: 6), const _FromHealth()],
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}

class _SexQuestion extends ConsumerWidget {
  const _SexQuestion({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aboutYouProvider);
    final c = ref.read(aboutYouProvider.notifier);
    return StepLayout(
      footer: _footer(
        busy: s.busy,
        onContinue: s.sex == null ? null : () => _confirm(ref, AboutQuestion.sex, onNext),
        onSkip: onNext,
      ),
      children: [
        const MascotLine(line: 'Two choices, as the tables go.', state: MascotState.thinking),
        const StepTitle(
          'What is your sex?',
          subtitle:
              'Used by the Mifflin-St Jeor equation for your resting energy, and by the fiber and '
              'calorie floor tables, which differ by sex.',
        ),
        for (final (i, (value, label, icon)) in const [
          ('male', 'Male', Icons.male_rounded),
          ('female', 'Female', Icons.female_rounded),
        ].indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ChoiceCard(
            icon: icon,
            title: label,
            selected: s.sex == value,
            onTap: () => c.setSex(value),
          ),
        ],
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}

String paceCaps(GoalKind kind) => switch (kind) {
  GoalKind.lose => 'Losing is capped at 1% of your body weight a week, whatever pace you pick.',
  GoalKind.gain =>
    'Gaining is held to 0.5% of your body weight a week when your target is worked out.',
  GoalKind.maintain => 'Your calorie target keeps your weight where it is.',
};

class _GoalQuestion extends ConsumerWidget {
  const _GoalQuestion({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aboutYouProvider);
    final c = ref.read(aboutYouProvider.notifier);
    return StepLayout(
      footer: _footer(
        busy: s.busy,
        onContinue: () => _confirm(ref, AboutQuestion.goal, onNext),
        onSkip: onNext,
      ),
      children: [
        const MascotLine(line: 'Slow and steady counts.', state: MascotState.happy),
        const StepTitle(
          'What is your weight goal?',
          subtitle:
              'Sets how far your calories sit from maintenance and how much protein you need '
              'for your weight.',
        ),
        for (final (i, (kind, title, sub, icon)) in const [
          (GoalKind.lose, 'Lose', 'Eat a little under maintenance', Icons.trending_down_rounded),
          (GoalKind.maintain, 'Maintain', 'Stay where I am', Icons.trending_flat_rounded),
          (GoalKind.gain, 'Gain', 'Eat a little over maintenance', Icons.trending_up_rounded),
        ].indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          ChoiceCard(
            icon: icon,
            title: title,
            subtitle: sub,
            selected: s.kind == kind,
            onTap: () => c.setKind(kind),
          ),
        ],
        if (s.kind != GoalKind.maintain) ...[
          const SizedBox(height: 20),
          const FieldLabel('Pace'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pace in s.kind == GoalKind.lose ? s.units.losePaces : s.units.gainPaces)
                LogChip(
                  label: s.units.pace(pace),
                  selected: s.pace == pace,
                  onTap: () => c.setPace(pace),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text(paceCaps(s.kind), style: AppText.caption),
        if (s.error != null) StepError(s.error!),
      ],
    );
  }
}

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aboutYouProvider);
    final loaded = ref.watch(targetsProvider);
    final report = loaded.value?.data;
    if (report == null) {
      if (!loaded.hasError) return const _Loading();
      return StepLayout(
        footer: [ChunkyButton(label: 'Done', onPressed: onNext)],
        children: const [
          MascotLine(line: 'Your answers are saved.', state: MascotState.sad),
          StepTitle(
            'Could not load your targets',
            subtitle: 'They are on Me > Targets whenever you are back online.',
          ),
        ],
      );
    }
    final targets = [for (final key in kReviewKeys) ?report.target(key)];
    final usableNow = [
      for (final t in targets)
        if (t.canUse) t,
    ];
    final stillNeeded = [
      for (final m in missingItems(report))
        if (m.key != 'pushupMax' && m.key != 'steps14') m.label,
    ];
    final applyAll = usableNow.isEmpty
        ? null
        : () async {
            final ok = await ref.read(aboutYouProvider.notifier).applyTargets([
              for (final t in usableNow) t.key,
            ]);
            if (!ok || !context.mounted) return;
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(appliedToast(usableNow))));
            onNext();
          };
    return StepLayout(
      footer: [
        if (applyAll != null) ...[
          ChunkyButton(label: 'Use all', busy: s.busy, onPressed: applyAll),
          ChunkyButton.secondary(label: 'Not now', onPressed: s.busy ? null : onNext),
        ] else
          ChunkyButton(label: 'Done', onPressed: onNext),
      ],
      children: [
        const MascotLine(line: 'Here is what the research says.', state: MascotState.cheer),
        const StepTitle(
          'Your daily targets',
          subtitle: 'Worked out from your answers with published formulas. Nothing is guessed.',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final (i, t) in targets.indexed) ...[
                if (i > 0) const Divider(height: 1, thickness: 2, color: kSunken),
                _TargetRow(target: t),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          stillNeeded.isEmpty
              ? 'Changes start tomorrow. This is general guidance, not medical advice.'
              : 'Still needed: ${stillNeeded.join(', ')}. This is general guidance, not medical '
                    'advice.',
          style: AppText.caption,
        ),
        if (s.applyError != null) StepError(s.applyError!),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target});

  final Target target;

  @override
  Widget build(BuildContext context) {
    final value = target.value;
    final name = targetName(target.key);
    final text = value == null ? 'Not yet' : formatTargetValue(value, target.unit);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$name, $text',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(name, style: AppText.body),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.end,
                style: AppText.tabular(
                  AppText.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: value == null ? kInkMuted : kInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
