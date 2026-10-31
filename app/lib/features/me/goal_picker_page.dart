import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/targets.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/preset_list.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import '../onboarding/goal_catalog.dart';
import 'goal_advice.dart';
import 'number_field.dart';

/// What the picker hands back.
class GoalChoice {
  const GoalChoice(this.target, this.targetAlt);

  final int target;
  final int? targetAlt;
}

/// The goals the server accepts for quests with a narrower range than "above zero", in the
/// quest's own unit (millilitres for water).
const kGoalRanges = {
  'water': (min: 250, max: 6000),
  'sleep_regularity': (min: 15, max: 120),
  'produce': (min: 1, max: 30),
  'breathing': (min: 1, max: 60),
};

/// One quest's goal: the recommendation for this person first, then other published figures or
/// plain numbers, and a number of your own.
class GoalPickerPage extends ConsumerStatefulWidget {
  const GoalPickerPage({
    super.key,
    required this.quest,
    required this.target,
    required this.targetAlt,
    this.units = Units.metric,
  });

  final QuestTemplate quest;
  final int target;
  final int? targetAlt;

  /// How a volume goal is read and typed.
  final Units units;

  @override
  ConsumerState<GoalPickerPage> createState() => _GoalPickerPageState();
}

class _GoalPickerPageState extends ConsumerState<GoalPickerPage> {
  late int? _value = widget.target;
  final TextEditingController _custom = TextEditingController();
  late final TextEditingController _alt = TextEditingController(
    text: widget.targetAlt?.toString() ?? '',
  );
  bool _prefilled = false;

  GoalSpec? get _spec => kGoalSpecs[widget.quest.key];

  bool get _isWater => widget.quest.key == 'water';

  /// The goal as typed: millilitres, or US fluid ounces for an imperial person's water.
  String _fieldText(int value) => _isWater && widget.units.isImperial
      ? (value / kMlPerFlOz).round().toString()
      : value.toString();

  int? _valueFrom(String text) {
    final typed = int.tryParse(text);
    if (typed == null || !_isWater) return typed;
    return widget.units.mlFromDrink(typed);
  }

  /// A starting goal that none of the listed choices matches shows in the number field, once the
  /// choices are known.
  void _prefill(Set<int> listed) {
    if (_prefilled) return;
    _prefilled = true;
    if (listed.contains(widget.target)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _value == widget.target) _custom.text = _fieldText(widget.target);
    });
  }

  @override
  void dispose() {
    _custom.dispose();
    _alt.dispose();
    super.dispose();
  }

  int? get _altValue => int.tryParse(_alt.text);

  bool get _valid =>
      (_value ?? 0) > 0 &&
      _inRange(_value!) &&
      (widget.quest.targetAlt == null || (_altValue ?? 0) > 0);

  bool _inRange(int value) {
    final range = kGoalRanges[widget.quest.key];
    return range == null || (value >= range.min && value <= range.max);
  }

  void _done() => Navigator.of(context).pop(GoalChoice(_value!, _altValue));

  void _choose(int v) {
    HapticFeedback.selectionClick();
    setState(() {
      _value = v;
      _custom.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    final spec = _spec;
    final palette = questPalette(q.key);
    final targets = ref.watch(targetsProvider);
    final report = targets.value?.data;
    final loading = spec?.targetKey != null && targets.isLoading && report == null;
    final advice = goalAdvice(q.key, report);
    final units = widget.units;

    final List<Widget> choices;
    final Set<int> listed;
    if (spec == null) {
      choices = const [];
      listed = {};
    } else if (loading) {
      choices = const [SkeletonBlock(height: 140, radius: 16)];
      listed = {};
    } else if (advice != null) {
      listed = {advice.value, for (final a in advice.alternatives) a.value};
      choices = [
        const SectionLabel('Recommended for you'),
        _RecommendedCard(
          advice: advice,
          label: spec.describe(advice.value, units),
          selected: _value == advice.value,
          palette: palette,
          onTap: () => _choose(advice.value),
        ),
        if (spec.note != null && advice.servingExamples.isEmpty) ...[
          const SizedBox(height: 10),
          Text(spec.note!, style: AppText.caption),
        ],
        if (advice.alternatives.isNotEmpty) ...[
          const SectionLabel('Other published figures'),
          PresetList<int>(
            palette: palette,
            presets: [
              for (final a in advice.alternatives)
                Preset(name: a.label, valueLabel: spec.describe(a.value, units), value: a.value),
            ],
            selected: advice.alternatives.any((a) => a.value == _value) ? _value : null,
            onChanged: _choose,
          ),
        ],
      ];
    } else {
      listed = {for (final o in spec.options) o.value};
      choices = [
        if (spec.targetKey != null)
          const _Note(
            'Your recommendation is not available yet. Add what is missing in Me > Targets.',
          )
        else if (spec.noResearch != null)
          _Note(spec.noResearch!),
        if (spec.note != null) ...[
          const SizedBox(height: 6),
          Text(spec.note!, style: AppText.caption),
        ],
        const SizedBox(height: 14),
        PresetList<int>(
          palette: palette,
          presets: [
            for (final o in spec.options)
              Preset(name: spec.describe(o.value, units), value: o.value),
          ],
          selected: listed.contains(_value) ? _value : null,
          onChanged: _choose,
        ),
      ];
    }
    if (!loading) _prefill(listed);

    return PageScaffold(
      title: spec?.question ?? q.title,
      footer: ChunkyButton(label: 'Done', palette: palette, onPressed: _valid ? _done : null),
      children: [
        ...choices,
        SizedBox(height: spec == null ? 0 : 20),
        NumberField(
          controller: _custom,
          label: spec == null ? 'Your goal' : 'Or type your own',
          hint: spec == null ? widget.target.toString() : 'Your number',
          unit: _isWater && units.isImperial ? 'fl oz' : shortUnit(q.unit),
          onChanged: () => setState(() => _value = _valueFrom(_custom.text) ?? _value),
        ),
        if (q.targetAlt != null) ...[
          const SizedBox(height: 16),
          NumberField(
            controller: _alt,
            label: 'Or, counting ${shortUnit(q.unitAlt ?? '')}',
            hint: '0',
            unit: shortUnit(q.unitAlt ?? ''),
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
  );
}

/// The figure for this person, with the one line that says where it comes from.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.advice,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final GoalAdvice advice;
  final String label;
  final bool selected;
  final AccentPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final examples = advice.servingExamples;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Recommended for you, $label. ${advice.why}',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        scale: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : kMotionDuration,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: selected ? palette.tint : kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: selected ? palette.fill : kBorder, width: kBorderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppText.tabular(
                        AppText.title.copyWith(color: selected ? palette.lip : kInk),
                      ),
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 24,
                    color: selected ? palette.lip : kInkMuted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(advice.why, style: AppText.body),
              if (examples.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'One serving is $kProduceServingGrams g, for example:',
                  style: AppText.caption,
                ),
                for (final e in examples) Text('- $e', style: AppText.caption),
              ],
              if (advice.cite.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Source: ${advice.cite}', style: AppText.caption.copyWith(color: kInkMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
