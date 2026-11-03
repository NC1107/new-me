import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../state/targets.dart';
import '../../state/units.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/reps_exercises.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../habits/habits_page.dart';
import '../onboarding/goal_catalog.dart';
import '../setup/about_you.dart';
import '../setup/about_you_page.dart';
import 'apple_health_page.dart';
import 'daily_reps_page.dart';
import 'goal_picker_page.dart';
import 'me_support.dart';
import 'number_field.dart';
import 'target_row.dart';
import 'target_sheet.dart';
import 'targets_logic.dart';

/// "8,000 steps", or "20 min or 15 pages" for a quest with two ways to finish it.
String goalLabel(QuestTemplate q, int target, int? alt, {Units units = Units.metric}) {
  final spec = kGoalSpecs[q.key];
  final main = q.key == 'pushups'
      ? '$target ${repsNoun(q.exercise, target)}'
      : spec?.describe(target, units) ?? '$target ${q.unit}';
  if (q.targetAlt == null || alt == null) return main;
  return '$main or $alt ${q.unitAlt ?? ''}'.trim();
}

/// The figures that are facts about the body or have no editor of their own; every other
/// recommendation leads its goal's picker instead of appearing twice.
const _kReferenceKeys = ['restingEnergy', 'maintenance', 'saturatedFatMax', 'fiber'];

/// Every goal in one place: the daily goals, the food numbers and the habits, each edited once.
/// Goal and food edits stay on the page until Save, which appears only once something changed.
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> with MeSaving {
  final _enabled = <String, bool>{};
  final _target = <String, int>{};
  final _alt = <String, int?>{};
  Map<String, QuestTemplate> _server = {};

  final _food = {
    'kcal': TextEditingController(),
    'protein': TextEditingController(),
    'carbs': TextEditingController(),
    'fat': TextEditingController(),
  };
  Targets _serverFood = const Targets();
  bool _foodAdopted = false;

  Set<String> _applying = {};
  String? _applyError;

  @override
  void initState() {
    super.initState();
    // Only a value the server changed replaces its draft, so saving another page keeps edits.
    ref.listenManual(meProvider, (_, next) {
      final me = next.value?.data;
      if (me != null) setState(() => _adopt(me));
    }, fireImmediately: true);
    // A held answer may predate a weigh-in or a profile edit made elsewhere.
    if (ref.exists(targetsProvider)) {
      Future.microtask(() {
        if (mounted) unawaited(ref.read(targetsProvider.notifier).refresh());
      });
    }
  }

  @override
  void dispose() {
    for (final c in _food.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _text(int? v) => v?.toString() ?? '';

  static int? _foodValue(Targets t, String key) => switch (key) {
    'kcal' => t.kcal,
    'protein' => t.protein,
    'carbs' => t.carbs,
    _ => t.fat,
  };

  void _adopt(Me me) {
    final before = _server;
    _server = {for (final q in me.questTemplates) q.key: q};
    for (final q in me.questTemplates) {
      final old = before[q.key];
      if (old != null &&
          old.enabled == q.enabled &&
          old.target == q.target &&
          old.targetAlt == q.targetAlt) {
        continue;
      }
      _enabled[q.key] = q.enabled;
      _target[q.key] = q.target.round();
      _alt[q.key] = q.targetAlt?.round();
    }
    final beforeFood = _serverFood;
    final first = !_foodAdopted;
    _foodAdopted = true;
    _serverFood = me.targets;
    for (final key in _food.keys) {
      final now = _foodValue(_serverFood, key);
      if (first || _foodValue(beforeFood, key) != now) _food[key]!.text = _text(now);
    }
  }

  List<QuestEdit> get _questEdits {
    final edits = <QuestEdit>[];
    for (final q in _server.values) {
      final enabledChanged = _enabled[q.key] != q.enabled;
      final targetChanged = _target[q.key] != q.target.round();
      final altChanged = q.targetAlt != null && _alt[q.key] != q.targetAlt!.round();
      if (!enabledChanged && !targetChanged && !altChanged) continue;
      edits.add(
        QuestEdit(
          key: q.key,
          enabled: enabledChanged ? _enabled[q.key] : null,
          target: targetChanged ? _target[q.key] : null,
          targetAlt: altChanged ? _alt[q.key] : null,
        ),
      );
    }
    return edits;
  }

  /// Only the edits: a new number, or null for a field emptied from a value.
  Map<String, int?> get _foodChanges {
    final out = <String, int?>{};
    for (final entry in _food.entries) {
      final current = _foodValue(_serverFood, entry.key);
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

  bool get _dirty => _questEdits.isNotEmpty || _foodChanges.isNotEmpty;

  Future<void> _pick(QuestTemplate q) async {
    final choice = await editGoal(context, ref, q, target: _target[q.key]!, targetAlt: _alt[q.key]);
    if (choice == null || !mounted) return;
    setState(() {
      _enabled[q.key] = true;
      _target[q.key] = choice.target;
      if (q.targetAlt != null) _alt[q.key] = choice.targetAlt;
    });
  }

  void _toggle(QuestTemplate q, bool on) {
    HapticFeedback.selectionClick();
    setState(() => _enabled[q.key] = on);
  }

  Future<void> _save() async {
    final edits = _questEdits;
    final patch = MePatch.targets(_foodChanges, questTemplates: edits.isEmpty ? null : edits);
    if (await saveMe(patch) && mounted) {
      toast('Saved');
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _apply(List<Target> targets) async {
    if (_applying.isNotEmpty || targets.isEmpty) return;
    setState(() {
      _applying = {for (final t in targets) t.key};
      _applyError = null;
    });
    try {
      final applied = await ref.read(targetsProvider.notifier).apply([
        for (final t in targets) t.key,
      ]);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      toast(
        appliedToast([
          for (final t in targets)
            if (applied.contains(t.key)) t,
        ], units: ref.read(unitsProvider)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _applyError = errorCopy(e));
    } finally {
      if (mounted) setState(() => _applying = {});
    }
  }

  Future<void> _fix(MissingItem item) async {
    switch (item.fix) {
      case FixAt.aboutYou:
        await pushPage(context, AboutYouPage(start: item.question ?? AboutQuestion.birthYear));
      case FixAt.health:
        await pushPage(context, const AppleHealthPage());
      case FixAt.pushupMax:
        await pushPage(context, const DailyRepsPage());
    }
    if (mounted) unawaited(ref.read(targetsProvider.notifier).refresh());
  }

  Widget _foodField(String key, String label, String unit, bool editable) => NumberField(
    controller: _food[key]!,
    label: label,
    unit: unit,
    clearable: true,
    editable: editable,
    onChanged: () => setState(() {}),
  );

  /// Null until there is something to save, so the bar is never an empty slot.
  Widget? _footer(bool editable) {
    if (!_dirty && saveError == null && !saving) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saveError != null) SaveError(saveError!),
        ChunkyButton(
          label: saveError != null ? 'Try again' : 'Save',
          busy: saving,
          onPressed: editable && _dirty ? _save : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Goals');
    if (view.placeholder != null) return view.placeholder!;
    final editable = view.editable;
    final units = ref.watch(unitsProvider);
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final held = ref.watch(targetsProvider).value;
    final report = held != null && held.userId == userId ? held.data : null;
    final quests = [...view.me!.questTemplates]..sort((a, b) => a.position.compareTo(b.position));
    return PageScaffold(
      title: 'Goals',
      banner: view.banner,
      footer: _footer(editable),
      children: [
        ..._recommendations(report, enabled: editable),
        const SectionLabel('Daily goals'),
        for (final (i, q) in quests.indexed) ...[
          if (i > 0) const SizedBox(height: kCardGap),
          _QuestGoalCard(
            quest: q,
            enabled: _enabled[q.key] ?? q.enabled,
            label: goalLabel(q, _target[q.key] ?? q.target.round(), _alt[q.key], units: units),
            editable: editable,
            onToggle: (on) => _toggle(q, on),
            onOpen: () => _pick(q),
          ),
        ],
        const SectionLabel('Food'),
        _foodField('kcal', 'Calories', 'kcal', editable),
        const SizedBox(height: 16),
        _foodField('protein', 'Protein', 'g', editable),
        const SizedBox(height: 16),
        _foodField('carbs', 'Carbs', 'g', editable),
        const SizedBox(height: 16),
        _foodField('fat', 'Fat', 'g', editable),
        const SectionLabel('Habits'),
        const HabitsSection(),
        ..._reference(report, units, enabled: editable),
      ],
    );
  }

  /// The button that sets every goal to its recommended figure, and the inputs still missing.
  List<Widget> _recommendations(TargetsReport? report, {required bool enabled}) {
    if (report == null) return const [];
    final usableTargets = usable(report);
    final missing = missingItems(report);
    return [
      if (_applyError != null) SaveError(_applyError!),
      if (usableTargets.isNotEmpty)
        ChunkyButton(
          label: 'Use all recommended (${usableTargets.length})',
          busy: _applying.length > 1,
          onPressed: enabled && _applying.isEmpty ? () => _apply(usableTargets) : null,
        )
      else if (report.targets.any((t) => t.isApplied && t.applicable))
        const _AllMatchNote(),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: 16),
        _MissingCard(items: missing, onFix: _fix),
      ],
    ];
  }

  /// Figures about the body and the ones with no goal of their own, with how they are worked out.
  List<Widget> _reference(TargetsReport? report, Units units, {required bool enabled}) {
    if (report == null) return const [];
    final targets = [for (final key in _kReferenceKeys) ?report.target(key)];
    if (targets.isEmpty) return const [];
    final estimate = report.target(kEstimateKey);
    return [
      const SectionLabel('Recommended figures'),
      const TargetColumnHeads(hasYours: false),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, t) in targets.indexed) ...[
              if (i > 0) const Divider(height: 0, thickness: kBorderWidth, color: kBorder),
              TargetRow(
                target: t,
                hasYours: false,
                units: units,
                onTap: () => showTargetSheet(
                  context,
                  target: t,
                  report: report,
                  estimate: t.key == 'maintenance' && estimate?.value != null ? estimate : null,
                  hasYours: false,
                  enabled: enabled && _applying.isEmpty,
                  units: units,
                  onUse: () => _apply([t]),
                  onMaxTest: () => _fix(kPushupMaxItem),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _AllMatchNote extends StatelessWidget {
  const _AllMatchNote();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.check_circle_rounded, size: 20, color: kSuccess),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Your goals match the recommendations.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _MissingCard extends StatelessWidget {
  const _MissingCard({required this.items, required this.onFix});

  final List<MissingItem> items;
  final void Function(MissingItem item) onFix;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Add these to work out your goals',
            style: AppText.headline.copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: '${item.label}. ${item.hint}',
            onTap: () => onFix(item),
            child: Pressable(
              scale: 0.99,
              onTap: () => onFix(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label, style: AppText.body),
                            Text(item.hint, style: AppText.caption),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: kInkMuted),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// One daily goal: tap the row to change its number, flip the switch to turn it on or off.
/// Borders stay neutral and the switch uses the person's colour; only the icon and the figure
/// carry the goal's own colour.
class _QuestGoalCard extends StatelessWidget {
  const _QuestGoalCard({
    required this.quest,
    required this.enabled,
    required this.label,
    required this.editable,
    required this.onToggle,
    required this.onOpen,
  });

  final QuestTemplate quest;
  final bool enabled;
  final String label;
  final bool editable;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette(quest.key);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final body = Row(
      children: [
        AnimatedContainer(
          duration: reduce ? Duration.zero : kMotionDuration,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? palette.tint : kSunken,
            shape: BoxShape.circle,
          ),
          child: Icon(questIcon(quest.key), size: 26, color: enabled ? palette.lip : kInkMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                quest.title,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w800,
                  color: enabled ? kInk : kInkSecondary,
                ),
              ),
              Text(
                enabled ? label : 'Off',
                style: AppText.tabular(
                  AppText.caption.copyWith(
                    color: enabled ? palette.lip : kInkMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: '${quest.title}, ${enabled ? label : 'off'}. Change goal',
              onTap: editable ? onOpen : null,
              child: Pressable(
                scale: 0.99,
                onTap: editable ? onOpen : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 76),
                  child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 0, 12), child: body),
                ),
              ),
            ),
          ),
          Semantics(
            label: quest.title,
            child: AppSwitch(value: enabled, onChanged: editable ? onToggle : null),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
