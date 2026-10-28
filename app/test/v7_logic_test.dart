import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/insights/body_insights.dart';
import 'package:newme/features/me/schedule_page.dart';
import 'package:newme/features/progress/lookback_card.dart';
import 'package:newme/features/progress/milestone_copy.dart';
import 'package:newme/features/progress/progress_logic.dart';
import 'package:newme/features/streaks/away_page.dart';
import 'package:newme/features/streaks/cover_card.dart';
import 'package:newme/features/streaks/repair_card.dart';
import 'package:newme/features/streaks/streak_visuals.dart';
import 'package:newme/features/today/streak_sheet.dart';
import 'package:newme/reminders/quiet_hours.dart';
import 'package:newme/reminders/reminder_plan.dart';

ProgressMetric _metric({
  String key = 'reading_minutes',
  String title = 'Reading',
  String unit = 'min a day',
  GoodDirection good = GoodDirection.up,
  double? current,
  double? previous,
  double? first,
  MetricChange? vsPrevious,
  MetricChange? vsFirst,
}) => ProgressMetric(
  key: key,
  title: title,
  unit: unit,
  goodDirection: good,
  current: current,
  previous: previous,
  first: first,
  changeFromPrevious: vsPrevious,
  changeFromFirst: vsFirst,
);

BoardUser _user(int id, {int freezes = 0, List<DayMark> last7 = const []}) => BoardUser(
  id: id,
  name: 'U$id',
  color: 'green',
  today: const BoardDay(points: 0, percent: 0, counted: false),
  week: 0,
  season: 0,
  streak: 0,
  last7: last7,
  freezes: Freezes(held: freezes),
);

DayMark _mark(String date, {bool counted = false, bool frozen = false, bool away = false}) =>
    DayMark(date: date, percent: 0, counted: counted, rest: false, frozen: frozen, away: away);

void main() {
  group('arrows follow the number and colour the direction', () {
    test('a rise in a good direction is up and good', () {
      final t = trendOf(const MetricChange(abs: 6, pct: 33.3, better: true));
      expect((t.movement, t.tone), (Movement.up, Tone.good));
    });

    test('a fall where lower is better is down and good', () {
      final t = trendOf(const MetricChange(abs: -6, pct: -9.4, better: true));
      expect((t.movement, t.tone), (Movement.down, Tone.good));
    });

    test('a fall where higher is better is down and bad', () {
      final t = trendOf(const MetricChange(abs: -680, pct: -7.5, better: false));
      expect((t.movement, t.tone), (Movement.down, Tone.bad));
    });

    test('weight has no good direction, so its arrow is neutral', () {
      final t = trendOf(const MetricChange(abs: -0.7, pct: -0.8));
      expect((t.movement, t.tone), (Movement.flat, Tone.neutral), reason: 'under 1% is flat');
      final big = trendOf(const MetricChange(abs: -3, pct: -3.5));
      expect((big.movement, big.tone), (Movement.down, Tone.neutral));
    });

    test('no change and a missing change are flat and neutral', () {
      expect(trendOf(const MetricChange(abs: 0, pct: 0)).movement, Movement.flat);
      expect(trendOf(null).tone, Tone.neutral);
    });

    test('the card follows the previous window, then the first', () {
      const first = MetricChange(abs: 1);
      const previous = MetricChange(abs: 2);
      expect(headlineChange(_metric(vsPrevious: previous, vsFirst: first)), previous);
      expect(headlineChange(_metric(vsFirst: first)), first);
      expect(headlineChange(_metric()), isNull);
    });
  });

  group('the plain sentence', () {
    test('reading against the first month', () {
      final m = _metric(current: 24, previous: 18, first: 11);
      expect(metricSentence(m), 'Reading: 24 min a day, up from 11 in your first month');
    });

    test('without a first window it compares with the previous one', () {
      final m = _metric(current: 24, previous: 30);
      expect(metricSentence(m), 'Reading: 24 min a day, down from 30 in the previous month');
    });

    test('equal numbers are about the same', () {
      expect(
        metricSentence(_metric(current: 24, first: 24)),
        'Reading: 24 min a day, about the same as in your first month',
      );
    });

    test('a lone number and no number', () {
      expect(metricSentence(_metric(current: 24)), 'Reading: 24 min a day');
      expect(metricSentence(_metric()), 'Reading: no data yet');
    });

    test('other windows name their days', () {
      final m = _metric(current: 5, first: 2);
      expect(
        metricSentence(m, window: 60),
        'Reading: 5 min a day, up from 2 in your first 60 days',
      );
      expect(previousWindowLabel(7), 'the previous 7 days');
    });

    test('sleep reads as hours and minutes and never splits across lines', () {
      final m = _metric(
        key: 'sleep_minutes',
        title: 'Sleep',
        unit: 'min a night',
        current: 437,
        first: 410,
      );
      expect(
        metricSentence(m),
        'Sleep: 7 h 17 min a night, up from 6 h 50 min in your first month',
      );
    });

    test('values keep one decimal, thousands separators and no trailing zero', () {
      expect(formatMetricValue('steps', 8420), '8,420');
      expect(formatMetricValue('weight_kg', 82.44), '82.4');
      expect(formatMetricValue('workouts', 3.0), '3');
    });
  });

  group('comparisons', () {
    test('sizes carry their sign and percent', () {
      expect(changeLabel('reading_minutes', const MetricChange(abs: 6, pct: 33.3)), '+6 (+33%)');
      expect(changeLabel('steps', const MetricChange(abs: -680, pct: -7.5)), '-680 (-8%)');
      expect(changeLabel('steps', const MetricChange(abs: 5)), '+5');
    });

    test('a comparison says better or worse in words', () {
      expect(
        comparisonLabel(
          'steps',
          'the previous month',
          const MetricChange(abs: -680, pct: -7.5, better: false),
        ),
        '-680 (-8%) vs the previous month, worse',
      );
      expect(
        comparisonLabel(
          'reading_minutes',
          'your first month',
          const MetricChange(abs: 13, pct: 118, better: true),
        ),
        '+13 (+118%) vs your first month, better',
      );
      expect(
        comparisonLabel('sleep_minutes', 'the previous month', const MetricChange(abs: 0, pct: 0)),
        'About the same as the previous month',
      );
      expect(comparisonLabel('steps', 'the previous month', null), contains('Not enough days'));
    });

    test('weight rate in words', () {
      expect(weeklyRateLabel(-0.34, Units.metric), 'down 0.3 kg a week');
      expect(weeklyRateLabel(0.5, Units.metric), 'up 0.5 kg a week');
      expect(weeklyRateLabel(0.02, Units.metric), 'steady');
      expect(weeklyRateLabel(null, Units.metric), isNull);
    });
  });

  test('metrics keep a stable order with unknown ones last', () {
    final ordered = orderedMetrics([
      _metric(key: 'zzz'),
      _metric(key: 'steps'),
      _metric(key: 'reading_minutes'),
      _metric(key: 'aaa'),
    ]);
    expect(ordered.map((m) => m.key), ['reading_minutes', 'steps', 'zzz', 'aaa']);
  });

  group('improvements and months', () {
    test('an improvement sentence follows the number, not the word better', () {
      const up = Improvement(
        key: 'pushups',
        title: 'Push-ups',
        unit: 'a day',
        value: 40,
        previous: 32,
        pct: 25,
        summary: '',
      );
      const down = Improvement(
        key: 'resting_hr',
        title: 'Resting heart rate',
        unit: 'bpm',
        value: 56,
        previous: 60,
        pct: 6.7,
        summary: '',
      );
      expect(improvementSentence(up), 'Push-ups: 40 a day, up from 32');
      expect(improvementSentence(down), 'Resting heart rate: 56 bpm, down from 60');
      expect(improvementPct(up), '+25%');
    });

    test('months shift across years', () {
      expect(shiftMonth('2026-10', -1), '2026-09');
      expect(shiftMonth('2026-01', -1), '2025-12');
      expect(shiftMonth('2026-12', 1), '2027-01');
      expect(lookbackMonthFor('2026-11-01'), '2026-10');
    });

    test('the look-back card quotes the couple, then anyone, then a prompt', () {
      Improvement imp(String t) =>
          Improvement(key: 'k', title: t, unit: 'u', value: 2, previous: 1, pct: 100, summary: '');
      expect(
        lookbackHeadline(
          Lookback(
            month: '2026-09',
            label: 'September 2026',
            couple: CoupleMonth(improvements: [imp('Couple')]),
            people: [
              PersonMonth(userId: 1, name: 'A', color: 'green', improvements: [imp('Mine')]),
            ],
          ),
          Units.metric,
        ),
        'Couple: 2 u, up from 1',
      );
      expect(
        lookbackHeadline(
          Lookback(
            month: '2026-09',
            label: 'September 2026',
            people: [
              PersonMonth(userId: 1, name: 'A', color: 'green', improvements: [imp('Mine')]),
            ],
          ),
          Units.metric,
        ),
        'Mine: 2 u, up from 1',
      );
      expect(
        lookbackHeadline(const Lookback(month: '2026-09', label: 'September 2026'), Units.metric),
        contains('how the month went'),
      );
    });
  });

  group('milestone words', () {
    Milestone m(String kind, int value, {bool shared = false}) => Milestone(
      id: 1,
      kind: kind,
      value: value,
      shared: shared,
      title: 'T',
      achievedOn: '2026-10-27',
    );

    test('streaks have a number and a sentence, firsts a star', () {
      expect(milestoneNumber(m('streak', 30)), '30');
      expect(milestoneBody(m('streak', 30)), '30 days in a row. That is real consistency.');
      expect(
        milestoneBody(m('shared_streak', 7, shared: true)),
        contains('both counted for 7 days'),
      );
      expect(milestoneNumber(m('first_10k_steps', 0)), isNull);
      expect(milestoneBody(m('first_10k_steps', 0)), 'A first, and now it is yours.');
      expect(milestoneOwner(m('streak', 7)), 'You');
      expect(milestoneOwner(m('shared_streak', 7, shared: true)), 'Together');
    });
  });

  group('freezes, repair and cover', () {
    test('the next freeze reads as progress, or why it waits', () {
      expect(
        freezeProgressLabel(const Freezes(held: 1, earnedTowardNext: 4)),
        '4 of 7 counted days to your next freeze - 3 to go',
      );
      expect(
        freezeProgressLabel(const Freezes(held: 2, earnedTowardNext: 6)),
        contains('the most you can'),
      );
      expect(freezesLabel(1), '1 streak freeze');
      expect(freezesLabel(2), '2 streak freezes');
    });

    test('a day shows one status, counted first', () {
      DayMark mark({
        bool counted = false,
        bool frozen = false,
        bool away = false,
        bool repaired = false,
        bool rest = false,
      }) => DayMark(
        date: '2026-10-26',
        percent: 0,
        counted: counted,
        rest: rest,
        frozen: frozen,
        away: away,
        repaired: repaired,
      );
      expect(dayStatus(mark(counted: true, frozen: true)), DayStatus.counted);
      expect(dayStatus(mark(repaired: true, frozen: true)), DayStatus.repaired);
      expect(dayStatus(mark(frozen: true)), DayStatus.frozen);
      expect(dayStatus(mark(away: true)), DayStatus.away);
      expect(dayStatus(mark(rest: true)), DayStatus.rest);
      expect(dayStatus(mark()), DayStatus.none);
      expect(dayStatus(mark(), counted: true), DayStatus.counted, reason: 'today may count early');
      expect(DayStatus.frozen.label, 'frozen day');
    });

    test('the repair card says what is missing, then that it is done', () {
      final repair = Repair(
        date: '2026-10-26',
        until: DateTime.utc(2026, 10, 28, 2),
        progressPercent: 36,
      );
      expect(repairCopy(repair, 36).title, 'Repair yesterday');
      expect(repairCopy(repair, 36).body, startsWith('You missed Monday. Reach 100% today before'));
      expect(repairCopy(repair, 100).title, 'Yesterday is repaired');
      expect(weekdayLong('2026-10-26'), 'Monday');
    });

    group('covering the partner', () {
      final me = _user(2, freezes: 1);
      const yesterday = '2026-10-26';
      final missed = _user(1, last7: [_mark(yesterday)]);
      final morning = DateTime(2026, 10, 27, 8);

      test('offered when they missed, hold none, and I hold one', () {
        expect(
          coverableDate(me: me, partner: missed, localToday: '2026-10-27', now: morning),
          yesterday,
        );
      });

      test('not offered after 10:00, without my freeze, or when they hold one', () {
        expect(
          coverableDate(
            me: me,
            partner: missed,
            localToday: '2026-10-27',
            now: DateTime(2026, 10, 27, 10),
          ),
          isNull,
        );
        expect(
          coverableDate(me: _user(2), partner: missed, localToday: '2026-10-27', now: morning),
          isNull,
        );
        expect(
          coverableDate(
            me: me,
            partner: _user(1, freezes: 1, last7: [_mark(yesterday)]),
            localToday: '2026-10-27',
            now: morning,
          ),
          isNull,
        );
      });

      test('not offered for a day that counted, froze or was away', () {
        for (final mark in [
          _mark(yesterday, counted: true),
          _mark(yesterday, frozen: true),
          _mark(yesterday, away: true),
        ]) {
          expect(
            coverableDate(
              me: me,
              partner: _user(1, last7: [mark]),
              localToday: '2026-10-27',
              now: morning,
            ),
            isNull,
          );
        }
        expect(
          coverableDate(me: me, partner: _user(1), localToday: '2026-10-27', now: morning),
          isNull,
        );
      });

      test('a refusal reads as a sentence', () {
        expect(
          sentenceCase('that day can no longer be covered'),
          'That day can no longer be covered.',
        );
        expect(
          coverError(const ApiException('x', code: 'no_freeze')),
          'You have no freeze to spend.',
        );
        expect(
          coverError(const ApiException('that day is closed', code: 'cover_closed')),
          'That day is closed.',
        );
      });
    });
  });

  group('away words', () {
    test('a day, a span and its length', () {
      expect(awayRangeLabel('2026-10-30', '2026-10-30'), 'Fri 30 Oct');
      expect(awayRangeLabel('2026-10-30', '2026-11-01'), 'Fri 30 Oct to Sun 1 Nov');
      expect(awayLengthLabel('2026-10-30', '2026-10-30'), '1 day');
      expect(awayLengthLabel('2026-10-30', '2026-11-01'), '3 days');
    });

    test('an overlap is explained', () {
      expect(
        awayError(const ApiException('x', code: 'away_overlap')),
        contains('already have away days'),
      );
    });
  });

  group('schedule', () {
    test('workdays read the way people say them', () {
      expect(workdaysLabel([1, 2, 3, 4, 5]), 'Mon to Fri');
      expect(workdaysLabel([6, 7]), 'Weekends');
      expect(workdaysLabel([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(workdaysLabel([]), 'No workdays');
      expect(workdaysLabel([1, 3]), 'Mon, Wed');
    });

    test('the first notification offset', () {
      expect(offsetLabel(0), 'As soon as you wake');
      expect(offsetLabel(10), '10 min after you wake');
      expect(
        firstNotificationAt(const DayTimes(wake: 6 * 60 + 30, bed: 23 * 60), 15),
        formatReminderTime(6 * 60 + 45),
      );
    });

    test('parses, applies workdays and survives garbage', () {
      final s = Schedule.parse({
        'workdays': [1, 2, 3, 9, 'x'],
        'workday': {'wake': '06:30', 'bed': '22:15'},
        'dayOff': {'wake': 'soon', 'bed': '23:30'},
        'firstNotificationOffsetMin': 500,
      });
      expect(s.workdays, [1, 2, 3]);
      expect(s.workday, const DayTimes(wake: 390, bed: 22 * 60 + 15));
      expect(
        s.dayOff,
        const DayTimes(wake: 420, bed: 23 * 60 + 30),
        reason: 'a bad time keeps the default',
      );
      expect(s.firstNotificationOffsetMin, 120, reason: 'clamped to the server maximum');
      expect(s.timesFor(DateTime.monday), s.workday);
      expect(s.timesFor(DateTime.sunday), s.dayOff);
      expect(Schedule.parse('nope'), const Schedule());
      expect(Schedule.parse(null).firstNotificationOffsetMin, 10);
    });

    test('clock strings round trip', () {
      expect(parseClock('07:05'), 425);
      expect(parseClock('24:00'), isNull);
      expect(parseClock('7'), isNull);
      expect(formatClockWire(425), '07:05');
    });
  });

  group('quiet hours', () {
    const schedule = Schedule(
      workday: DayTimes(wake: 6 * 60 + 30, bed: 22 * 60 + 30),
      dayOff: DayTimes(wake: 9 * 60, bed: 23 * 60 + 30),
      firstNotificationOffsetMin: 30,
    );
    // 2026-10-26 is a Monday (a workday), 2026-10-31 a Saturday.
    DateTime monday(int h, int m) => DateTime(2026, 10, 26, h, m);

    test('the night and the wait for the first notification are quiet', () {
      expect(inQuietHours(monday(3, 0), schedule), isTrue);
      expect(inQuietHours(monday(6, 59), schedule), isTrue);
      expect(inQuietHours(monday(7, 0), schedule), isFalse);
      expect(inQuietHours(monday(22, 29), schedule), isFalse);
      expect(inQuietHours(monday(22, 30), schedule), isTrue);
    });

    test('days off use their own times', () {
      expect(inQuietHours(DateTime(2026, 10, 31, 8, 59), schedule), isTrue);
      expect(inQuietHours(DateTime(2026, 10, 31, 9, 30), schedule), isFalse);
    });

    test('a bedtime after midnight only leaves the morning quiet', () {
      const late = Schedule(
        workday: DayTimes(wake: 9 * 60, bed: 60),
        firstNotificationOffsetMin: 0,
      );
      expect(inQuietHours(monday(8, 0), late), isTrue);
      expect(inQuietHours(monday(23, 0), late), isFalse);
    });
  });

  group('the evening reminder respects quiet hours, habit reminders do not', () {
    const schedule = Schedule(
      workday: DayTimes(wake: 7 * 60, bed: 21 * 60),
      firstNotificationOffsetMin: 10,
    );
    final morning = DateTime(2026, 10, 26, 8);

    test('a reminder before bedtime is planned as before', () {
      final plan = planReminders(now: morning, minutes: 20 * 60, schedule: schedule);
      expect(plan[kTonightReminderId]?.at, DateTime(2026, 10, 26, 20));
      expect(plan[kTomorrowReminderId]?.at, DateTime(2026, 10, 27, 20));
    });

    test('a reminder after bedtime is not scheduled at all', () {
      final plan = planReminders(now: morning, minutes: 22 * 60, schedule: schedule);
      expect(plan[kTonightReminderId], isNull);
      expect(plan[kTomorrowReminderId], isNull);
    });

    test('without a schedule nothing changes', () {
      final plan = planReminders(now: morning, minutes: 22 * 60);
      expect(plan[kTonightReminderId], isNotNull);
    });
  });

  group('insights words', () {
    test('weight reads as one decimal and a trend', () {
      expect(weightLabel(82.44, Units.metric), '82.4\u00a0kg');
      const falling = WeightInsights(smoothedKg: 82.4, weeklyRateKg: -0.4);
      expect(weightTrendLabel(falling, Units.metric), 'down 0.4 kg a week');
      expect(
        weightTrendIcon(falling).codePoint,
        isNot(weightTrendIcon(const WeightInsights()).codePoint),
      );
      expect(weightTrendLabel(const WeightInsights(smoothedKg: 82.4), Units.metric), isNull);
    });

    test('aerobic minutes against the WHO range', () {
      ActivitySummary a(int equivalent) => ActivitySummary(moderateEquivalentMin: equivalent);
      expect(aerobicBand(a(100)), AerobicBand.below);
      expect(aerobicStatus(a(110)), 'Short by 40 min');
      expect(aerobicBand(a(150)), AerobicBand.inRange);
      expect(aerobicBand(a(300)), AerobicBand.inRange);
      expect(aerobicStatus(a(200)), 'In the 150 to 300 range');
      expect(aerobicBand(a(301)), AerobicBand.above);
      expect(aerobicStatus(a(400)), 'Above the range');
    });

    test('strength days against two', () {
      expect(strengthStatus(const ActivitySummary(strengthDays: 0)), '2 more days');
      expect(strengthStatus(const ActivitySummary(strengthDays: 1)), '1 more day');
      expect(strengthStatus(const ActivitySummary(strengthDays: 3)), 'Done');
      expect(
        activitySentence(const ActivitySummary(moderateEquivalentMin: 285, strengthDays: 1)),
        '285 moderate-equivalent minutes against 150 to 300 (In the 150 to 300 range), and 1 strength day against 2.',
      );
    });

    test('the protein hit rate and its basis', () {
      expect(proteinHitLabel(const ProteinHitRate(daysHit7: 5, days7: 7)), '5 of the last 7 days');
      expect(proteinHitLabel(const ProteinHitRate(daysHit7: 1, days7: 1)), '1 of the last 1 day');
      expect(
        proteinBasis(
          const ProteinHitRate(targetG: 100, suggestedG: 130, perKg: 1.6, weightKg: 82.4),
          Units.metric,
        ),
        'Target 100 g. At 1.6 g per kg and 82.4\u00a0kg the default would be 130 g.',
      );
      expect(
        proteinBasis(
          const ProteinHitRate(targetG: 130, suggestedG: 130, perKg: 1.6, weightKg: 82.4),
          Units.metric,
        ),
        'Target 130 g a day.',
      );
      expect(proteinBasis(const ProteinHitRate(), Units.metric), isNull);
    });
  });
}
