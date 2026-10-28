import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/me.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../onboarding/goal_catalog.dart';
import 'goal_picker_page.dart';
import 'me_support.dart';

/// "8,000 steps", or "20 min or 15 pages" for a quest with two ways to finish it.
String goalLabel(QuestTemplate q, int target, int? alt) {
  final spec = kGoalSpecs[q.key];
  final main = spec?.label(target) ?? '$target ${q.unit}';
  if (q.targetAlt == null || alt == null) return main;
  return '$main or $alt ${q.unitAlt ?? ''}'.trim();
}

/// Turn each quest on or off and set its daily goal. Edits stay on the page until Save.
class DailyGoalsPage extends ConsumerStatefulWidget {
  const DailyGoalsPage({super.key});

  @override
  ConsumerState<DailyGoalsPage> createState() => _DailyGoalsPageState();
}

class _DailyGoalsPageState extends ConsumerState<DailyGoalsPage> with MeSaving {
  final _enabled = <String, bool>{};
  final _target = <String, int>{};
  final _alt = <String, int?>{};
  Map<String, QuestTemplate> _server = {};

  @override
  void initState() {
    super.initState();
    // Only a quest the server changed replaces its draft, so saving another page keeps these edits.
    ref.listenManual(meProvider, (_, next) {
      final me = next.value?.data;
      if (me != null) setState(() => _adopt(me));
    }, fireImmediately: true);
  }

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
  }

  List<QuestEdit> get _edits {
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

  Future<void> _pick(QuestTemplate q) async {
    final choice = await pushPage<GoalChoice>(
      context,
      GoalPickerPage(quest: q, target: _target[q.key]!, targetAlt: _alt[q.key]),
    );
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
    if (await saveMe(MePatch(questTemplates: _edits)) && mounted) {
      toast('Saved');
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Daily goals');
    if (view.placeholder != null) return view.placeholder!;
    final quests = [...view.me!.questTemplates]..sort((a, b) => a.position.compareTo(b.position));
    return PageScaffold(
      title: 'Daily goals',
      banner: view.banner,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveError != null) SaveError(saveError!),
          ChunkyButton(
            label: saveError != null ? 'Try again' : 'Save',
            busy: saving,
            onPressed: view.editable && _edits.isNotEmpty ? _save : null,
          ),
        ],
      ),
      children: [
        const _TomorrowNote(),
        const SizedBox(height: 16),
        for (final (i, q) in quests.indexed) ...[
          if (i > 0) const SizedBox(height: kCardGap),
          _QuestGoalCard(
            quest: q,
            enabled: _enabled[q.key] ?? q.enabled,
            label: goalLabel(q, _target[q.key] ?? q.target.round(), _alt[q.key]),
            editable: view.editable,
            onToggle: (on) => _toggle(q, on),
            onOpen: () => _pick(q),
          ),
        ],
      ],
    );
  }
}

class _TomorrowNote extends StatelessWidget {
  const _TomorrowNote();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.wb_twilight_rounded, size: 20, color: questPalette('exercise').lip),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'Changes start tomorrow, so today keeps the goals you began it with.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

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
        if (enabled) const Icon(Icons.chevron_right_rounded, color: kInkMuted),
      ],
    );
    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: enabled ? palette.fill : kBorder,
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
            child: Switch(
              value: enabled,
              onChanged: editable ? onToggle : null,
              activeThumbColor: palette.onFill,
              activeTrackColor: palette.fill,
              inactiveTrackColor: kSunken,
              inactiveThumbColor: kInkMuted,
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? palette.fill : kBorder,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
