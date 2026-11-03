import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/reps_exercises.dart';
import '../../widgets/info_note.dart';
import '../me/targets_logic.dart';
import '../onboarding/goal_catalog.dart';

/// The target in `GET /api/targets` that explains a quest's number, or null where the number is
/// the person's own pick and no published research sets it.
String? targetKeyForQuest(String questKey) => switch (questKey) {
  'steps' ||
  'protein' ||
  'sleep' ||
  'water' ||
  'produce' ||
  'breathing' ||
  'pushups' ||
  'exercise' ||
  // The pages way to finish it follows from the minutes; the minutes themselves are the
  // person's pick.
  'reading' => questKey,
  _ => null,
};

/// How far a goal may sit from the recommendation and still read as "a little" above or below.
const _nearShare = 0.2;

/// What "Why this goal" says for one quest, in the order it is read.
class QuestWhy {
  const QuestWhy({
    this.recommended,
    this.reason,
    this.yours,
    this.comparison,
    this.citation,
    this.formula,
    this.note,
  });

  /// "Recommended: 27 push-ups a day, 3 sets of 9": the figure in the quest's own unit.
  final String? recommended;

  /// One plain line on where the figure comes from.
  final String? reason;

  /// "Yours is 4,500 steps.": the person's own goal, shown beside [recommended].
  final String? yours;

  /// How the person's own goal compares with [recommended].
  final String? comparison;

  /// "Source: Zourdos et al., J Strength Cond Res 2016", shown inside the expander.
  final String? citation;

  /// The precise working, kept out of the way behind a tap.
  final String? formula;

  /// A plain sentence that stands in for the rest where there is no recommendation to give.
  final String? note;
}

/// The goal or recommendation in the quest's own unit, "27 push-ups" or "7 h 30 min".
String _amount(Quest quest, String key, int value, Units units) => switch (key) {
  'steps' => '${value.formatted} steps',
  'pushups' => '${value.formatted} ${repsNoun(quest.exercise, value)}',
  'water' => units.volume(value),
  'protein' => '${value.formatted} g',
  'produce' => '${value.formatted} ${value == 1 ? 'serving' : 'servings'}',
  'reading' => '${value.formatted} ${value == 1 ? 'page' : 'pages'}',
  _ => formatTargetValue(value, quest.unit, units: units),
};

String _recommendedLine(Quest quest, Target target, Units units) {
  final v = target.value!;
  final amount = _amount(quest, quest.key, v, units);
  final line = switch (quest.key) {
    'steps' => '$amount a day',
    'pushups' => '$amount a day${_setsText(target)}',
    'sleep' => '$amount of sleep a night',
    'water' => '$amount of drinks a day',
    'protein' => '$amount of protein a day',
    'produce' => '$amount of fruit and veg a day (${v * kProduceServingGrams} g)',
    'breathing' => '$amount of breathing a day',
    'reading' => '$amount for your ${quest.target.round()} minutes',
    _ => '$amount a day',
  };
  return 'Recommended: $line';
}

/// ", 3 sets of 9" for the push-up style quests, from the numbers the server worked out.
String _setsText(Target target) {
  final sets = target.details['sets'];
  final reps = target.details['repsPerSet'];
  if (sets is! num || reps is! num || sets < 2) return '';
  // Non-breaking spaces keep "3 sets of 9" from splitting across lines.
  return ', ${sets.round()}\u00a0sets\u00a0of\u00a0${reps.round()}';
}

String _compare(Quest quest, int goal, int recommended, Units units) {
  final amount = _amount(quest, quest.key, goal, units);
  if (goal == recommended) return 'Your goal is $amount, the same as the recommendation.';
  final near = (goal - recommended).abs() <= recommended * _nearShare;
  final side = goal > recommended ? 'above' : 'below';
  return 'Your goal is $amount, ${near ? 'a little ' : ''}$side the recommendation.';
}

String _yours(Quest quest, int goal, Units units) =>
    'Yours is ${_amount(quest, quest.key, goal, units)}.';

/// The goal in plain words for quests that have no recommendation, or null where a single
/// number does not say it (reading counts minutes or pages).
String? _ownGoal(Quest quest, Units units) {
  if (quest.targetAlt != null || quest.key == 'sleep_regularity') return null;
  return formatTargetValue(quest.target.round(), quest.unit, units: units);
}

/// Everything the section says, or null while the report has not loaded or the server has
/// nothing to say about the quest.
QuestWhy? questWhy(Quest quest, TargetsReport? report, Units units) {
  final key = targetKeyForQuest(quest.key);
  if (key == null) {
    final goal = _ownGoal(quest, units);
    final own = goal == null ? 'the goal is your own pick' : 'your goal of $goal is your own pick';
    if (quest.key == 'sleep_regularity') {
      return QuestWhy(
        note: 'Steady sleep and wake times matter, but no research gives a cut-off, so $own.',
        citation: report == null ? null : 'Source: ${report.citation('phillips2017')}',
      );
    }
    return QuestWhy(note: 'No published research sets a number for this, so $own.');
  }
  final target = report?.target(key);
  if (target == null || target.formula.isEmpty) return null;
  final citation = target.sources.isEmpty
      ? null
      : 'Source: ${report!.citation(target.sources.first)}';
  if (target.value == null) {
    return QuestWhy(note: target.formula, citation: citation);
  }
  final sameUnit = target.unit == quest.unit;
  final note = target.details['note'];
  final why = [
    if (target.why.isNotEmpty) target.why,
    if (quest.key == 'reading' && note is String) note,
  ].join(' ');
  final pagesGoal = quest.key == 'reading' ? quest.targetAlt?.round() : null;
  return QuestWhy(
    recommended: _recommendedLine(quest, target, units),
    reason: why.isEmpty ? null : why,
    yours: pagesGoal != null
        ? _yours(quest, pagesGoal, units)
        : sameUnit
        ? _yours(quest, quest.target.round(), units)
        : null,
    comparison: pagesGoal != null
        ? _compare(quest, pagesGoal, target.value!, units)
        : sameUnit
        ? _compare(quest, quest.target.round(), target.value!, units)
        : null,
    citation: citation,
    formula: target.formula,
  );
}

/// "Why this goal": the recommendation and the person's own number in one line, with the reason,
/// the working and the source behind an info row.
class QuestWhySection extends StatelessWidget {
  const QuestWhySection({super.key, required this.why});

  final QuestWhy why;

  @override
  Widget build(BuildContext context) {
    final label = why.formula != null ? 'How this is worked out' : 'Where this comes from';
    final detail = [?why.reason, ?why.comparison, ?why.formula];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (why.recommended != null)
          Text(
            why.yours == null ? why.recommended! : '${why.recommended!}. ${why.yours!}',
            style: AppText.body.copyWith(fontWeight: FontWeight.w800),
          ),
        if (why.note != null) Text(why.note!, style: AppText.body),
        if (detail.isNotEmpty || why.citation != null)
          InfoNote(
            label,
            style: AppText.label.copyWith(color: kInkSecondary),
            info: InfoContent(title: 'Why this goal', paragraphs: detail, source: why.citation),
          ),
      ],
    );
  }
}
