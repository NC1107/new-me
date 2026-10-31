import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../state/targets.dart';
import '../../state/today.dart';
import '../../state/units.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/quest_copy.dart';
import '../../widgets/thick_progress_bar.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../me/goal_picker_page.dart';
import '../me/targets_logic.dart';
import '../../widgets/page_scaffold.dart';
import 'day_detail_sheet.dart';

/// The target in `GET /api/targets` that explains a quest's number, or null where the number is
/// the person's own pick and no published research sets it.
String? targetKeyForQuest(String questKey) => switch (questKey) {
  'steps' || 'protein' || 'sleep' || 'water' || 'produce' || 'breathing' || 'pushups' => questKey,
  'exercise' => 'activity',
  _ => null,
};

/// Where a mixed quest's progress comes from when it was not logged in New Me.
const _otherSource = {
  'exercise': 'Apple Health',
  'breathing': 'Apple Health',
  'water': 'Apple Health',
  'yoga': 'Apple Health',
  'reading': 'audiobook listening',
  'pushups': 'a strength session',
};

/// Where a quest's number comes from, in one short line.
String questSourceLine(String key) => switch (key) {
  'steps' => 'Counted by Apple Health',
  'sleep' => 'Counted by Apple Health from your sleep',
  'sleep_regularity' => 'Worked out from your Apple Health sleep',
  'exercise' => 'Apple Health workouts, plus any activity you log',
  'breathing' => 'Breathing you log, plus Apple Health mindful minutes',
  'water' => 'Water you log, plus any Apple Health records',
  'pushups' => 'A strength session, or reps you log',
  'reading' => 'Reading you log, plus linked audiobook listening',
  'yoga' => 'Yoga you log, or a yoga workout from Apple Health',
  'meals_logged' => 'Counted from the meals you log',
  'protein' => 'Added up from the meals you log',
  'produce' => 'Servings you log',
  _ => 'Counted from what you log',
};

/// Whether a logged entry feeds the quest, so the sheet lists only that quest's entries.
bool entryFeedsQuest(String questKey, LogEntry entry) => switch (entry) {
  MealLog() => questKey == 'meals_logged' || questKey == 'protein',
  ActivityLog(:final type) => switch (questKey) {
    'exercise' => type == 'other',
    _ => type == questKey,
  },
};

/// "+100 points, 24% of today", or "Earned ..." once the quest is done.
String questWorthLine(Quest q, int dayMax) {
  final share = dayMax > 0 && q.points <= dayMax
      ? ', ${(q.points * 100 / dayMax).round()}% of today'
      : '';
  return q.done ? 'Earned +${q.points} points$share' : '+${q.points} points$share';
}

/// What the sheet hands back, so the caller can offer Undo on the page behind it.
enum QuestSheetResult { turnedOff }

/// The quest's detail: progress, worth, its own entries, the last days, why the goal is what it
/// is, and the actions on it. Returns [QuestSheetResult.turnedOff] when the quest was switched off.
Future<QuestSheetResult?> showQuestSheet(BuildContext context, {required String questKey}) =>
    showAppSheet<QuestSheetResult>(context, builder: (_) => QuestSheet(questKey: questKey));

class QuestSheet extends ConsumerStatefulWidget {
  const QuestSheet({super.key, required this.questKey});

  final String questKey;

  @override
  ConsumerState<QuestSheet> createState() => _QuestSheetState();
}

class _QuestSheetState extends ConsumerState<QuestSheet> {
  List<QuestDay>? _history;
  bool _historyFailed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      final days = await client.questHistory(widget.questKey);
      if (mounted) setState(() => _history = days);
    } on ApiException {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  QuestTemplate? get _template => ref
      .read(meProvider)
      .value
      ?.data
      .questTemplates
      .where((t) => t.key == widget.questKey)
      .firstOrNull;

  Future<void> _save(QuestEdit edit) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(meProvider.notifier).save(MePatch(questTemplates: [edit]));
      HapticFeedback.lightImpact();
      if (mounted) unawaited(_loadHistory());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeGoal() async {
    final t = _template;
    if (t == null) return;
    final choice = await pushPage<GoalChoice>(
      context,
      GoalPickerPage(
        quest: t,
        target: t.target.round(),
        targetAlt: t.targetAlt?.round(),
        units: ref.read(unitsProvider),
      ),
    );
    if (choice == null || !mounted) return;
    final targetChanged = choice.target != t.target.round();
    final altChanged = t.targetAlt != null && choice.targetAlt != t.targetAlt!.round();
    if (!targetChanged && !altChanged) return;
    await _save(
      QuestEdit(
        key: t.key,
        target: targetChanged ? choice.target : null,
        targetAlt: altChanged ? choice.targetAlt : null,
      ),
    );
  }

  Future<void> _turnOff(Quest q) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Turn off ${q.title}?',
      message:
          'It leaves today and your daily total right away. '
          'You can turn it back on from Me, Daily goals.',
      confirmLabel: 'Turn off',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _save(QuestEdit(key: q.key, enabled: false));
    if (mounted && _error == null) Navigator.of(context).pop(QuestSheetResult.turnedOff);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider).value?.data;
    final quest = today?.quests.where((q) => q.key == widget.questKey).firstOrNull;
    final height = MediaQuery.sizeOf(context).height * 0.88;
    if (today == null || quest == null) return SizedBox(height: height);
    final units = ref.watch(unitsProvider);
    final kind = LogKind.forQuest(quest.key);

    return ScaffoldMessenger(
      child: SizedBox(
        height: height,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              kGutter,
              0,
              kGutter,
              kGutter + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _Header(quest: quest, units: units),
              const SizedBox(height: 16),
              _ProgressBlock(quest: quest, dayMax: today.day.maxBase, units: units),
              const SizedBox(height: 24),
              _Section(title: 'Today', child: _entries(quest, today.localToday)),
              const SizedBox(height: 24),
              _Section(title: 'Last 7 days', child: _week(quest)),
              ..._why(quest),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: AppText.label.copyWith(color: kDangerText)),
                ),
              if (kind != null) ...[
                ChunkyButton(
                  label: quest.key == 'exercise' ? 'Log an activity' : kind.title,
                  icon: Icons.add_rounded,
                  onPressed: () => showLogSheet(context, kind: kind),
                ),
                const SizedBox(height: kCardGap),
              ],
              ChunkyButton.secondary(
                label: 'Change goal',
                icon: Icons.tune_rounded,
                busy: _busy,
                onPressed: _template == null ? null : _changeGoal,
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _turnOff(quest),
                  style: TextButton.styleFrom(
                    foregroundColor: kDangerText,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text(
                    'Turn off this quest',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entries(Quest quest, String date) {
    if (isAutomaticQuest(quest.key) && quest.key != 'exercise') {
      return Text(
        'Nothing to log here. ${questSourceLine(quest.key)}.',
        style: AppText.body.copyWith(color: kInkSecondary),
      );
    }
    return EntryList(
      date: date,
      shrinkWrap: true,
      matches: (e) => entryFeedsQuest(quest.key, e),
      // A Health-fed quest can have progress with no entry of its own to list.
      emptyText: quest.actual > 0 && _otherSource[quest.key] != null
          ? 'Nothing logged here yet. What counts so far came from ${_otherSource[quest.key]}.'
          : 'Nothing logged for this yet.',
    );
  }

  Widget _week(Quest quest) {
    final days = _history;
    if (days == null) {
      return Text(
        _historyFailed ? 'Could not load the last days.' : 'Loading...',
        style: AppText.body.copyWith(color: kInkSecondary),
      );
    }
    return QuestWeek(days: days, questKey: quest.key);
  }

  /// The formula's number is a suggestion; a goal set to something else is said to be the
  /// person's own, so the sentence above never reads as the reason for a different number.
  bool _differs(Quest quest, Target target) =>
      target.value != null && target.unit == quest.unit && target.value != quest.target.round();

  String _goalText(Quest quest, Target target) =>
      formatTargetValue(quest.target.round(), target.unit, units: ref.watch(unitsProvider));

  List<Widget> _why(Quest quest) {
    final key = targetKeyForQuest(quest.key);
    final report = ref.watch(targetsProvider).value?.data;
    final target = key == null ? null : report?.target(key);
    if (key != null && (target == null || target.formula.isEmpty)) return const [];
    return [
      const SizedBox(height: 24),
      _Section(
        title: 'Why this goal',
        child: key == null
            ? Text(
                'No published research sets this number. It is the goal you picked.',
                style: AppText.body.copyWith(color: kInkSecondary),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(target!.formula, style: AppText.body),
                  if (_differs(quest, target)) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Your goal is ${_goalText(quest, target)}, which is your own pick.',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                  ],
                  if (target.sources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(report!.citation(target.sources.first), style: AppText.caption),
                  ],
                ],
              ),
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(header: true, child: Text(title, style: AppText.headline)),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.quest, required this.units});

  final Quest quest;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final category = questPalette(quest.key);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: category.tint, shape: BoxShape.circle),
          child: Icon(questIcon(quest.key), size: 26, color: category.lip),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(questTitle(quest, units: units), style: AppText.title),
              ),
              const SizedBox(height: 2),
              Text(
                questSourceLine(quest.key),
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.quest, required this.dayMax, required this.units});

  final Quest quest;
  final int dayMax;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final category = questPalette(quest.key);
    final ink = context.accentText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          questProgress(quest, units: units),
          style: AppText.tabular(AppText.headline.copyWith(fontSize: 17)),
        ),
        const SizedBox(height: 8),
        ThickProgressBar(
          value: questFraction(quest),
          color: quest.done ? person.fill : category.fill,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              quest.done ? Icons.check_circle_rounded : Icons.bolt_rounded,
              size: 18,
              color: quest.done ? ink : kInkSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                questWorthLine(quest, dayMax),
                style: AppText.label.copyWith(
                  color: quest.done ? ink : kInkSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (quest.bonusPoints > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${quest.bonusPoints} bonus for finishing it',
              style: AppText.caption.copyWith(color: kInkSecondary),
            ),
          ),
      ],
    );
  }
}

/// The last days of one quest: a bar per day, filled to how far it got, with the weekday under it.
class QuestWeek extends StatelessWidget {
  const QuestWeek({super.key, required this.days, required this.questKey});

  final List<QuestDay> days;
  final String questKey;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Always seven slots, so a person who joined this week still sees a week, with the days before
  /// they joined left empty.
  static List<QuestDay> _padded(List<QuestDay> days) {
    final first = days.isEmpty ? null : DateTime.tryParse(days.first.date);
    if (first == null || days.length >= 7) return days;
    return [
      for (var back = 7 - days.length; back > 0; back--)
        QuestDay(
          date: first.subtract(Duration(days: back)).toIso8601String().substring(0, 10),
          tracked: false,
          actual: 0,
          target: 0,
          unit: '',
          done: false,
        ),
      ...days,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final category = questPalette(questKey);
    final slots = _padded(days);
    final tracked = days.where((d) => d.tracked).toList();
    final done = tracked.where((d) => d.done).length;
    final summary = tracked.isEmpty
        ? 'Not part of your days yet.'
        : 'Done on $done of ${tracked.length} ${tracked.length == 1 ? 'day' : 'days'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary, style: AppText.label.copyWith(color: kInkSecondary)),
        const SizedBox(height: 10),
        Semantics(
          label: summary,
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, d) in slots.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _DayBar(
                    day: d,
                    fill: d.done ? person.fill : category.fill,
                    tint: category.tint,
                    isToday: i == slots.length - 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.fill, required this.tint, required this.isToday});

  final QuestDay day;
  final Color fill;
  final Color tint;
  final bool isToday;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    final weekday = DateTime.tryParse(day.date)?.weekday;
    final letter = weekday == null ? '' : QuestWeek._weekdays[weekday - 1];
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: day.tracked ? tint : kSunken,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              if (day.tracked)
                FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: day.done ? 1 : day.fraction.clamp(0.06, 1),
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
                    child: day.done
                        ? Center(
                            child: Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: context.accentPalette.onFill,
                            ),
                          )
                        : null,
                  ),
                )
              else
                const Center(
                  child: Text('-', style: TextStyle(color: kInkMuted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          letter,
          style: AppText.caption.copyWith(
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? kInk : kInkSecondary,
          ),
        ),
      ],
    );
  }
}
