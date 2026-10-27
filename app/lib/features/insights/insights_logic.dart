import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../util/format.dart';
import '../../widgets/quest_copy.dart';
import '../health/health_metrics.dart';

/// "23:10" as minutes after midnight, or null when it is not a clock time.
int? clockMinutes(String? hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm ?? '');
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// "23:10" as "11:10 PM".
String clockLabel(String? hhmm) {
  final minutes = clockMinutes(hhmm);
  if (minutes == null) return '-';
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));
}

String timeLabel(DateTime t) => DateFormat('h:mm a').format(t);

/// Bedtimes between midnight and noon are "late"; the evening ones are not.
const _lateBedtimeCutoff = 12 * 60;
const _shortSleepGapMin = 30;
const _wideSpreadMin = 45;

class SleepTip {
  const SleepTip(this.text, {this.positive = false});

  final String text;

  /// A note that nothing needs fixing, shown instead of tips.
  final bool positive;
}

/// Up to two gentle tips from the sleep numbers, most useful first. With nothing to improve it is a
/// single positive note; with no sleep data at all it is empty.
List<SleepTip> sleepTips(SleepInsights s) {
  final average = s.avg7Min ?? s.avg30Min;
  final bed = clockMinutes(s.avgBedtime);
  if (average == null && bed == null && s.bedtimeSpreadMin == null) return const [];

  final tips = <SleepTip>[];
  if (bed != null && bed > 0 && bed < _lateBedtimeCutoff) {
    tips.add(
      const SleepTip(
        'You usually fall asleep after midnight. Moving bedtime 15 minutes earlier each night '
        'is an easy way to start.',
      ),
    );
  }
  if (average != null && average <= s.targetMin - _shortSleepGapMin) {
    final gap = (s.targetMin - average).round();
    tips.add(
      SleepTip(
        'You are averaging ${durationLabel(gap)} less than your ${durationLabel(s.targetMin)} '
        'target. An earlier wind-down is the simplest fix.',
      ),
    );
  }
  final spread = s.bedtimeSpreadMin;
  if (spread != null && spread > _wideSpreadMin) {
    tips.add(
      const SleepTip(
        'Your bedtime moves around a lot. A steadier time, even at weekends, helps you fall '
        'asleep faster.',
      ),
    );
  }
  if (tips.isEmpty) {
    return const [
      SleepTip(
        'Your sleep looks steady and on target. Keep doing what you are doing.',
        positive: true,
      ),
    ];
  }
  return tips.take(2).toList();
}

/// "Your bedtime varies by about 40 minutes"; steady below five minutes of spread.
String consistencyLine(num spreadMin) {
  final rounded = (spreadMin / 5).round() * 5;
  if (rounded < 5) return 'Your bedtime is very steady';
  return 'Your bedtime varies by about ${durationLabel(rounded)}';
}

enum SleepStage { deep, core, rem, awake }

String sleepStageName(SleepStage s) => switch (s) {
  SleepStage.deep => 'Deep',
  SleepStage.core => 'Core',
  SleepStage.rem => 'REM',
  SleepStage.awake => 'Awake',
};

int stageMinutes(SleepStages s, SleepStage stage) => switch (stage) {
  SleepStage.deep => s.deepMin,
  SleepStage.core => s.coreMin,
  SleepStage.rem => s.remMin,
  SleepStage.awake => s.awakeMin,
};

Map<SleepStage, int> stageMap(SleepStages s) => {
  for (final stage in SleepStage.values) stage: stageMinutes(s, stage),
};

int stageTotal(SleepStages s) => s.deepMin + s.coreMin + s.remMin + s.awakeMin;

/// What the suggestion card says, split so the headline can be large.
class StepSuggestionCopy {
  const StepSuggestionCopy({required this.headline, required this.reason});

  final String headline;
  final String reason;
}

StepSuggestionCopy stepSuggestionCopy(StepSuggestion s, {int? goal}) {
  final median = s.median14.round();
  final range = '${s.bandLow.formatted} to ${s.bandHigh.formatted}';
  final who = s.ageKnown ? 'for your age' : 'for adults';
  final target = s.target.formatted;
  if (s.target == goal) {
    return StepSuggestionCopy(
      headline: 'Stay at $target a day',
      reason:
          'You have averaged ${median.formatted} over two weeks, and most of the benefit $who '
          'comes by $range. Your goal already fits.',
    );
  }
  if (s.target > median) {
    return StepSuggestionCopy(
      headline: 'Try $target a day',
      reason:
          'You have averaged ${median.formatted} over two weeks, and most of the benefit $who '
          'comes by $range.',
    );
  }
  return StepSuggestionCopy(
    headline: 'Keep going at $target a day',
    reason:
        'You have averaged ${median.formatted} over two weeks, which is already at or above the '
        '$range range where most of the benefit $who comes. Keep doing what you do.',
  );
}

String trendLabel(String trend) => switch (trend) {
  'up' => 'Up on last week',
  'down' => 'Down on last week',
  _ => 'Steady',
};

/// "Today", "Yesterday", or "Mon, Oct 26" relative to [today].
String relativeDay(String date, String? today) {
  if (today != null) {
    if (date == today) return 'Today';
    if (date == previousDate(today)) return 'Yesterday';
  }
  return DateFormat.MMMEd().format(parseLocalDate(date));
}

String workoutCountLabel(int n) => '$n ${n == 1 ? 'workout' : 'workouts'}';

/// "5.2 km" or "850 m".
String distanceLabel(int meters) => healthMetricSpec('distance_m')!.format(meters);
