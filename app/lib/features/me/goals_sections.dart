import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import 'save_bar.dart';

final _digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)];

class TargetsSection extends ConsumerStatefulWidget {
  const TargetsSection({super.key, required this.me, required this.editable});

  final Me me;
  final bool editable;

  @override
  ConsumerState<TargetsSection> createState() => _TargetsSectionState();
}

class _TargetsSectionState extends ConsumerState<TargetsSection> {
  late final _kcal = TextEditingController(text: _text(widget.me.targets.kcal));
  late final _protein = TextEditingController(text: _text(widget.me.targets.protein));
  late final _carbs = TextEditingController(text: _text(widget.me.targets.carbs));
  late final _fat = TextEditingController(text: _text(widget.me.targets.fat));
  bool _saving = false;
  String? _error;

  static String _text(num? v) => v == null ? '' : v.round().toString();

  @override
  void didUpdateWidget(TargetsSection old) {
    super.didUpdateWidget(old);
    // Only a changed target replaces what is typed, so saving another section keeps the edits.
    final before = old.me.targets;
    final after = widget.me.targets;
    if (before.kcal != after.kcal) _kcal.text = _text(after.kcal);
    if (before.protein != after.protein) _protein.text = _text(after.protein);
    if (before.carbs != after.carbs) _carbs.text = _text(after.carbs);
    if (before.fat != after.fat) _fat.text = _text(after.fat);
  }

  @override
  void dispose() {
    for (final c in [_kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Null when the field is blank or unchanged, so only edits go to the server.
  int? _changed(TextEditingController c, int? current) {
    final v = int.tryParse(c.text);
    return v == null || v <= 0 || v == current ? null : v;
  }

  MePatch get _patch => MePatch(
    kcalTarget: _changed(_kcal, widget.me.targets.kcal),
    proteinTarget: _changed(_protein, widget.me.targets.protein),
    carbsTarget: _changed(_carbs, widget.me.targets.carbs),
    fatTarget: _changed(_fat, widget.me.targets.fat),
  );

  bool get _dirty => _patch.toJson().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meProvider.notifier).save(_patch);
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _saving = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field('Calories (kcal)', _kcal)),
              const SizedBox(width: 10),
              Expanded(child: _field('Protein (g)', _protein)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field('Carbs (g)', _carbs)),
              const SizedBox(width: 10),
              Expanded(child: _field('Fat (g)', _fat)),
            ],
          ),
          const SizedBox(height: 16),
          SaveBar(
            enabled: widget.editable && _dirty,
            saving: _saving,
            error: _error,
            onSave: _save,
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      IgnorePointer(
        ignoring: !widget.editable,
        child: AppTextField(
          controller: controller,
          hint: 'Not set',
          semanticLabel: label,
          keyboardType: TextInputType.number,
          inputFormatters: _digits,
          onChanged: (_) => setState(() {}),
        ),
      ),
    ],
  );
}

class QuestsSection extends ConsumerStatefulWidget {
  const QuestsSection({super.key, required this.me, required this.editable});

  final Me me;
  final bool editable;

  @override
  ConsumerState<QuestsSection> createState() => _QuestsSectionState();
}

class _QuestsSectionState extends ConsumerState<QuestsSection> {
  final _targets = <String, TextEditingController>{};
  final _targetsAlt = <String, TextEditingController>{};
  final _enabled = <String, bool>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(QuestsSection old) {
    super.didUpdateWidget(old);
    final before = {for (final q in old.me.questTemplates) q.key: q};
    _reset(unchangedFrom: before);
  }

  /// Fills the rows from the server's templates, leaving rows that match [unchangedFrom] alone
  /// so saving another section keeps what is typed here.
  void _reset({Map<String, QuestTemplate> unchangedFrom = const {}}) {
    for (final q in widget.me.questTemplates) {
      if (_sameEditableFields(unchangedFrom[q.key], q)) continue;
      _enabled[q.key] = q.enabled;
      (_targets[q.key] ??= TextEditingController()).text = q.target.round().toString();
      if (q.targetAlt != null) {
        (_targetsAlt[q.key] ??= TextEditingController()).text = q.targetAlt!.round().toString();
      }
    }
  }

  bool _sameEditableFields(QuestTemplate? a, QuestTemplate b) =>
      a != null && a.enabled == b.enabled && a.target == b.target && a.targetAlt == b.targetAlt;

  @override
  void dispose() {
    for (final c in [..._targets.values, ..._targetsAlt.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<QuestEdit> get _edits {
    final edits = <QuestEdit>[];
    for (final q in widget.me.questTemplates) {
      final enabled = _enabled[q.key]!;
      final target = int.tryParse(_targets[q.key]!.text);
      final alt = int.tryParse(_targetsAlt[q.key]?.text ?? '');
      final enabledChanged = enabled != q.enabled;
      final targetChanged = target != null && target > 0 && target != q.target.round();
      final altChanged =
          q.targetAlt != null && alt != null && alt > 0 && alt != q.targetAlt!.round();
      if (!enabledChanged && !targetChanged && !altChanged) continue;
      edits.add(
        QuestEdit(
          key: q.key,
          enabled: enabledChanged ? enabled : null,
          target: targetChanged ? target : null,
          targetAlt: altChanged ? alt : null,
        ),
      );
    }
    return edits;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meProvider.notifier).save(MePatch(questTemplates: _edits));
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _saving = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Takes effect tomorrow',
            style: TextStyle(color: kFgSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          for (final q in widget.me.questTemplates) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: kBorder),
            ),
            _questRow(q),
          ],
          const SizedBox(height: 16),
          SaveBar(
            enabled: widget.editable && _edits.isNotEmpty,
            saving: _saving,
            error: _error,
            onSave: _save,
          ),
        ],
      ),
    );
  }

  Widget _questRow(QuestTemplate q) {
    final enabled = _enabled[q.key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                q.title,
                style: const TextStyle(
                  color: kFgPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Semantics(
              label: q.title,
              child: Switch(
                value: enabled,
                onChanged: widget.editable
                    ? (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _enabled[q.key] = v);
                      }
                    : null,
                activeThumbColor: context.onAccent,
                activeTrackColor: context.accent,
              ),
            ),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _target(q.title, 'Target (${shortUnit(q.unit)})', _targets[q.key]!)),
              if (q.targetAlt != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _target(
                    q.title,
                    'Or (${shortUnit(q.unitAlt ?? '')})',
                    _targetsAlt[q.key]!,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _target(String questTitle, String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      IgnorePointer(
        ignoring: !widget.editable,
        child: AppTextField(
          controller: controller,
          hint: '0',
          semanticLabel: '$questTitle $label',
          keyboardType: TextInputType.number,
          inputFormatters: _digits,
          onChanged: (_) => setState(() {}),
        ),
      ),
    ],
  );
}
