import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/insights/insight_charts.dart';
import 'package:newme/features/insights/insights_logic.dart';
import 'package:newme/features/insights/sleep_insight_screen.dart';
import 'package:newme/features/insights/steps_insight_screen.dart';
import 'package:newme/features/insights/workout_types.dart';
import 'package:newme/theme/quest_style.dart';
import 'package:newme/theme/tokens.dart';

SleepInsights _sleep({
  num? avg7 = 450,
  num? avg30 = 450,
  int target = 450,
  String? bed = '23:00',
  num? spread = 20,
}) => SleepInsights(
  avg7Min: avg7,
  avg30Min: avg30,
  targetMin: target,
  avgBedtime: bed,
  avgWake: '07:00',
  bedtimeSpreadMin: spread,
);

void main() {
  group('sleepTips', () {
    test('a steady night on target gets a single positive note', () {
      final tips = sleepTips(_sleep());
      expect(tips, hasLength(1));
      expect(tips.single.positive, isTrue);
    });

    test('no data at all gives no tip', () {
      expect(sleepTips(const SleepInsights()), isEmpty);
    });

    test('a bedtime after midnight is called late, but midnight itself and evenings are not', () {
      expect(sleepTips(_sleep(bed: '00:40')).single.text, contains('after midnight'));
      expect(sleepTips(_sleep(bed: '02:15')).single.text, contains('after midnight'));
      expect(sleepTips(_sleep(bed: '00:00')).single.positive, isTrue);
      expect(sleepTips(_sleep(bed: '23:59')).single.positive, isTrue);
    });

    test('sleep 30 minutes or more under target is short, 29 is not', () {
      final short = sleepTips(_sleep(avg7: 420)).single;
      expect(short.text, contains('30 min less than your 7 h 30 min target'));
      expect(sleepTips(_sleep(avg7: 421)).single.positive, isTrue);
    });

    test('the 7 night average is preferred and the 30 night one is the fallback', () {
      expect(sleepTips(_sleep(avg7: 450, avg30: 300)).single.positive, isTrue);
      expect(sleepTips(_sleep(avg7: null, avg30: 300)).single.text, contains('less than'));
    });

    test('a spread over 45 minutes is flagged, 45 is not', () {
      expect(sleepTips(_sleep(spread: 46)).single.text, contains('moves around'));
      expect(sleepTips(_sleep(spread: 45)).single.positive, isTrue);
    });

    test('never more than two tips, most useful first', () {
      final tips = sleepTips(_sleep(bed: '01:00', avg7: 300, spread: 90));
      expect(tips, hasLength(2));
      expect(tips.first.text, contains('after midnight'));
      expect(tips.last.text, contains('less than'));
      expect(tips.every((t) => !t.positive), isTrue);
    });
  });

  group('copy', () {
    test('consistency reads as the doc example and rounds to five minutes', () {
      expect(consistencyLine(38.5), 'Your bedtime varies by about 40 min');
      expect(consistencyLine(62), 'Your bedtime varies by about 1 h');
      expect(consistencyLine(72), 'Your bedtime varies by about 1 h 10 min');
      expect(consistencyLine(2), 'Your bedtime is very steady');
    });

    test('clock times read in twelve hours', () {
      expect(clockLabel('23:10'), '11:10 PM');
      expect(clockLabel('06:50'), '6:50 AM');
      expect(clockLabel('00:05'), '12:05 AM');
      expect(clockLabel(null), '-');
      expect(clockLabel('late'), '-');
      expect(clockMinutes('25:00'), isNull);
    });

    test('the suggestion says why in plain words', () {
      const s = StepSuggestion(
        target: 8500,
        median14: 7400,
        bandLow: 8000,
        bandHigh: 10000,
        ageKnown: true,
      );
      final copy = stepSuggestionCopy(s);
      expect(copy.headline, 'Try 8,500 a day');
      expect(
        copy.reason,
        'You have averaged 7,400 over two weeks, and most of the benefit for your age comes by '
        '8,000 to 10,000.',
      );
    });

    test('without an age the reason says adults', () {
      const s = StepSuggestion(
        target: 8000,
        median14: 6500,
        bandLow: 7000,
        bandHigh: 10000,
        ageKnown: false,
      );
      expect(stepSuggestionCopy(s).reason, contains('for adults'));
    });

    test('at or above the range it says keep going; an equal goal says stay', () {
      const s = StepSuggestion(
        target: 10000,
        median14: 11000,
        bandLow: 8000,
        bandHigh: 10000,
        ageKnown: true,
      );
      expect(stepSuggestionCopy(s).headline, 'Keep going at 10,000 a day');
      expect(stepSuggestionCopy(s, goal: 10000).headline, 'Stay at 10,000 a day');
    });

    test('relative days', () {
      expect(relativeDay('2026-10-26', '2026-10-26'), 'Today');
      expect(relativeDay('2026-10-25', '2026-10-26'), 'Yesterday');
      expect(relativeDay('2026-10-20', '2026-10-26'), 'Tue, Oct 20');
    });
  });

  group('stage maths', () {
    test('totals and a map in stage order', () {
      const s = SleepStages(deepMin: 60, remMin: 90, coreMin: 240, awakeMin: 20);
      expect(stageTotal(s), 410);
      expect(stageMap(s).values, [60, 240, 90, 20]);
    });
  });

  group('chart slots', () {
    test('steps fill 30 days ending on the end date and leave gaps', () {
      final slots = stepSlots([
        const HealthTrendPoint(date: '2026-10-26', value: 9000),
        const HealthTrendPoint(date: '2026-10-24', value: 4000),
      ], '2026-10-26');
      expect(slots, hasLength(30));
      expect(slots.last.value, 9000);
      expect(slots[27].value, 4000);
      expect(slots[28].value, isNull);
      expect(slots.first.label, 'Sep 27');
    });

    test('sleep fills 14 mornings', () {
      final slots = sleepSlots(const [
        SleepNightPoint(date: '2026-10-26', asleepMin: 410),
      ], '2026-10-26');
      expect(slots, hasLength(14));
      expect(slots.last.value, 410);
      expect(slots.first.value, isNull);
    });
  });

  group('workout types', () {
    test('every type has a friendly name and its own icon', () {
      final icons = <Object>{};
      for (final t in WorkoutType.all) {
        expect(workoutTypeName(t), isNotEmpty);
        icons.add(workoutTypeIcon(t).codePoint);
      }
      expect(icons, hasLength(WorkoutType.all.length));
      expect(workoutTypeName('running'), 'Run');
      expect(workoutTypeName('something-new'), 'Workout');
      expect(workoutCountLabel(1), '1 workout');
      expect(workoutCountLabel(3), '3 workouts');
    });
  });

  group('contrast', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    test('every sleep stage colour reads at 3:1 against the white card', () {
      for (final s in SleepStage.values) {
        expect(ratio(sleepStageColor(s), kSurface), greaterThanOrEqualTo(3), reason: s.name);
      }
    });

    test('the insight accent text clears AA on white', () {
      for (final key in ['steps', 'sleep', 'exercise', 'meals']) {
        expect(ratio(questPalette(key).lip, kSurface), greaterThanOrEqualTo(4.5), reason: key);
      }
      expect(ratio(kInkMuted, kCanvas), greaterThanOrEqualTo(4.5));
    });

    test('the chart bar colours are visible against the white card', () {
      for (final key in ['steps', 'sleep']) {
        expect(ratio(questPalette(key).fill, kSurface), greaterThanOrEqualTo(3), reason: key);
      }
    });
  });
}
