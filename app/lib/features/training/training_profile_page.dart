import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../log/log_chip.dart';
import '../me/number_field.dart';
import '../../widgets/units_scope.dart';

/// Session lengths offered, inside the server's 20 to 90 minutes.
const kSessionMinutes = [20, 30, 45, 60, 75, 90];
const kMaxFocus = 300;

/// What plans are built for: equipment, days, minutes, experience and a focus in the person's
/// own words.
class TrainingProfilePage extends ConsumerStatefulWidget {
  const TrainingProfilePage({super.key, this.initial});

  final TrainingProfile? initial;

  @override
  ConsumerState<TrainingProfilePage> createState() => _TrainingProfilePageState();
}

class _TrainingProfilePageState extends ConsumerState<TrainingProfilePage> {
  late final TrainingProfile _start = widget.initial ?? const TrainingProfile();
  late final Set<String> _equipment = {..._start.equipment};
  late final Units _units = context.units;
  late final _dumbbell = TextEditingController(
    text: _start.dumbbellMaxKg == null
        ? ''
        : _units.weightIn(_start.dumbbellMaxKg!).round().formatted,
  );
  late final _focus = TextEditingController(text: _start.focus);
  late int _days = _start.daysPerWeek;
  late int _minutes = kSessionMinutes.contains(_start.sessionMinutes) ? _start.sessionMinutes : 45;
  late Experience _experience = _start.experience;
  bool _saving = false;
  String? _error;

  double? get _dumbbellValue => double.tryParse(_dumbbell.text.replaceAll(',', '.'));

  /// The heaviest dumbbell in kg, to the hundredth so a whole number of pounds survives.
  double? get _dumbbellKg {
    final v = _dumbbellValue;
    return v == null ? null : (_units.weightToKg(v) * 100).round() / 100;
  }

  bool get _dumbbellValid {
    if (!_equipment.contains('dumbbells') || _dumbbell.text.trim().isEmpty) return true;
    final kg = _dumbbellKg;
    return kg != null && kg > 0 && kg <= 200;
  }

  @override
  void dispose() {
    _dumbbell.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() {
    if (!_equipment.remove(key)) _equipment.add(key);
  });

  Future<void> _save() async {
    if (!_dumbbellValid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(trainingSetupProvider.notifier)
          .saveProfile(
            TrainingProfile(
              equipment: [
                for (final k in kEquipmentKeys)
                  if (_equipment.contains(k)) k,
              ],
              dumbbellMaxKg: _equipment.contains('dumbbells') && _dumbbell.text.trim().isNotEmpty
                  ? _dumbbellKg
                  : null,
              daysPerWeek: _days,
              sessionMinutes: _minutes,
              experience: _experience,
              focus: _focus.text.trim(),
            ),
          );
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Training setup',
      subtitle: 'Plans are designed around this.',
      footer: ChunkyButton(label: 'Save', busy: _saving, onPressed: _dumbbellValid ? _save : null),
      children: [
        const FieldLabel('Equipment you have'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in kEquipmentKeys)
              LogChip(
                label: equipmentLabel(key),
                selected: _equipment.contains(key),
                onTap: () => _toggle(key),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _equipment.isEmpty
              ? 'None selected: bodyweight exercises only.'
              : 'Full gym covers everything.',
          style: AppText.caption.copyWith(color: kInkMuted),
        ),
        if (_equipment.contains('dumbbells')) ...[
          const SizedBox(height: 16),
          NumberField(
            controller: _dumbbell,
            label: 'Heaviest dumbbell',
            hint: 'Not set',
            unit: _units.weightUnit,
            clearable: true,
            onChanged: () => setState(() {}),
          ),
          if (!_dumbbellValid) ...[
            const SizedBox(height: 6),
            Text(
              'Between 0 and ${_units.weightIn(200).round()} ${_units.weightUnit}',
              style: AppText.caption.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
        ],
        const SizedBox(height: 24),
        const FieldLabel('Days a week'),
        Row(
          children: [
            for (final d in [2, 3, 4, 5, 6]) ...[
              if (d > 2) const SizedBox(width: 8),
              Expanded(
                child: LogChip(
                  label: '$d',
                  compact: true,
                  selected: _days == d,
                  onTap: () => setState(() => _days = d),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'At least 2 days of muscle-strengthening work a week (WHO 2020).',
          style: AppText.caption.copyWith(color: kInkMuted),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Minutes a session'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kSessionMinutes)
              LogChip(
                label: '$m min',
                selected: _minutes == m,
                onTap: () => setState(() => _minutes = m),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const FieldLabel('Experience'),
        for (final e in Experience.values) ...[
          ChoiceCard(
            title: e.label,
            subtitle: switch (e) {
              Experience.newcomer => 'New to strength training, or back after a long break',
              Experience.some => 'Trained on and off for a few months',
              Experience.experienced => 'Trained consistently for a year or more',
            },
            selected: _experience == e,
            onTap: () => setState(() => _experience = e),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        const FieldLabel('Focus'),
        AppTextField(
          controller: _focus,
          hint: 'For example: first set of 10 pull-ups',
          semanticLabel: 'Focus',
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(kMaxFocus)],
          onChanged: (_) => setState(() {}),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(error, style: AppText.label.copyWith(color: kDangerText)),
        ],
      ],
    );
  }
}
