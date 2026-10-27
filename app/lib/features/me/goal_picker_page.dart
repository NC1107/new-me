import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../util/format.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/preset_list.dart';
import '../onboarding/goal_catalog.dart';
import 'number_field.dart';

/// What the picker hands back.
class GoalChoice {
  const GoalChoice(this.target, this.targetAlt);

  final int target;
  final int? targetAlt;
}

/// One quest's goal: the same named presets onboarding offers, plus a number of your own.
class GoalPickerPage extends StatefulWidget {
  const GoalPickerPage({
    super.key,
    required this.quest,
    required this.target,
    required this.targetAlt,
  });

  final QuestTemplate quest;
  final int target;
  final int? targetAlt;

  @override
  State<GoalPickerPage> createState() => _GoalPickerPageState();
}

class _GoalPickerPageState extends State<GoalPickerPage> {
  late int? _value = widget.target;
  late final TextEditingController _custom = TextEditingController(text: _customText());
  late final TextEditingController _alt = TextEditingController(
    text: widget.targetAlt?.toString() ?? '',
  );

  GoalSpec? get _spec => kGoalSpecs[widget.quest.key];

  String _customText() {
    final onPreset = _spec?.options.any((o) => o.value == widget.target) ?? false;
    return onPreset ? '' : widget.target.toString();
  }

  @override
  void dispose() {
    _custom.dispose();
    _alt.dispose();
    super.dispose();
  }

  int? get _altValue => int.tryParse(_alt.text);

  bool get _valid => (_value ?? 0) > 0 && (widget.quest.targetAlt == null || (_altValue ?? 0) > 0);

  void _done() => Navigator.of(context).pop(GoalChoice(_value!, _altValue));

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    final spec = _spec;
    final palette = questPalette(q.key);
    return PageScaffold(
      title: spec?.question ?? q.title,
      footer: ChunkyButton(label: 'Done', palette: palette, onPressed: _valid ? _done : null),
      children: [
        if (spec != null) ...[
          PresetList<int>(
            palette: palette,
            presets: [
              for (final o in spec.options)
                Preset(name: o.name, valueLabel: spec.label(o.value), value: o.value),
            ],
            selected: spec.options.any((o) => o.value == _value) ? _value : null,
            onChanged: (v) => setState(() {
              _value = v;
              _custom.clear();
            }),
          ),
          const SizedBox(height: 20),
        ],
        NumberField(
          controller: _custom,
          label: spec == null ? 'Your goal' : 'Or type your own',
          hint: spec == null ? widget.target.toString() : 'Your number',
          unit: shortUnit(q.unit),
          onChanged: () => setState(() => _value = int.tryParse(_custom.text) ?? _value),
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
