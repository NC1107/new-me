import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/me.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import 'me_support.dart';
import 'number_field.dart';

/// A PATCH /api/me that can also send `null` for a target, which clears it on the server.
/// [MePatch] leaves null fields out, so this sends the targets map itself.
/// Calories and macros. Empty a field and save to go back to having no target.
class FoodTargetsPage extends ConsumerStatefulWidget {
  const FoodTargetsPage({super.key});

  @override
  ConsumerState<FoodTargetsPage> createState() => _FoodTargetsPageState();
}

class _FoodTargetsPageState extends ConsumerState<FoodTargetsPage> with MeSaving {
  final _fields = {
    'kcal': TextEditingController(),
    'protein': TextEditingController(),
    'carbs': TextEditingController(),
    'fat': TextEditingController(),
  };
  Targets _server = const Targets();
  bool _adopted = false;

  static String _text(int? v) => v?.toString() ?? '';

  static int? _serverValue(Targets t, String key) => switch (key) {
    'kcal' => t.kcal,
    'protein' => t.protein,
    'carbs' => t.carbs,
    _ => t.fat,
  };

  @override
  void initState() {
    super.initState();
    // Only a target the server changed replaces what is typed, so saving another page keeps edits.
    ref.listenManual(meProvider, (_, next) {
      final me = next.value?.data;
      if (me == null) return;
      final before = _server;
      final first = !_adopted;
      _adopted = true;
      _server = me.targets;
      for (final key in _fields.keys) {
        final now = _serverValue(_server, key);
        if (first || _serverValue(before, key) != now) {
          _fields[key]!.text = _text(now);
        }
      }
      setState(() {});
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only the edits: a new number, or null for a field emptied from a value.
  Map<String, int?> get _changes {
    final out = <String, int?>{};
    for (final entry in _fields.entries) {
      final current = _serverValue(_server, entry.key);
      final typed = entry.value.text.trim();
      if (typed.isEmpty) {
        if (current != null) out[entry.key] = null;
        continue;
      }
      final v = int.tryParse(typed);
      if (v != null && v > 0 && v != current) out[entry.key] = v;
    }
    return out;
  }

  Future<void> _save() async {
    if (await saveMe(MePatch.targets(_changes)) && mounted) {
      toast('Saved');
      Navigator.of(context).maybePop();
    }
  }

  Widget _field(String key, String label, String unit, bool editable) => NumberField(
    controller: _fields[key]!,
    label: label,
    unit: unit,
    clearable: true,
    editable: editable,
    onChanged: () => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Food targets');
    if (view.placeholder != null) return view.placeholder!;
    final editable = view.editable;
    return PageScaffold(
      title: 'Food targets',
      banner: view.banner,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveError != null) SaveError(saveError!),
          ChunkyButton(
            label: saveError != null ? 'Try again' : 'Save',
            busy: saving,
            onPressed: editable && _changes.isNotEmpty ? _save : null,
          ),
        ],
      ),
      children: [
        Text(
          'Your food card tracks these. Leave one empty if you do not want a target for it.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        _field('kcal', 'Calories (kcal)', 'kcal', editable),
        const SizedBox(height: 16),
        _field('protein', 'Protein (g)', 'g', editable),
        const SizedBox(height: 16),
        _field('carbs', 'Carbs (g)', 'g', editable),
        const SizedBox(height: 16),
        _field('fat', 'Fat (g)', 'g', editable),
      ],
    );
  }
}
