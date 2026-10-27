import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';

import 'fixtures.dart';

void main() {
  group('older servers and bad rows parse to "nothing to show"', () {
    test('Today without any v7 field', () {
      final today = Today.fromJson(richTodayJson());
      expect(today.freezes.held, 0);
      expect(today.repair, isNull);
      expect(today.away.isEmpty, isTrue);
      expect(today.newMilestones, isEmpty);
      expect(today.toJson().containsKey('freezes'), isFalse, reason: 'cache stays as it was sent');
    });

    test('Today with garbage in the new fields', () {
      final today = Today.fromJson({
        ...richTodayJson(),
        'freezes': 'two',
        'repair': {'date': ''},
        'away': 7,
        'newMilestones': [
          {'id': 'x'},
          'nope',
          {
            'id': 3,
            'kind': 'streak',
            'value': 7,
            'shared': false,
            'title': '7-day streak',
            'achievedOn': '2026-10-27',
          },
        ],
      });
      expect(today.freezes.held, 0);
      expect(today.repair, isNull);
      expect(today.away.today, isFalse);
      expect(today.newMilestones.map((m) => m.id), [3]);
    });

    test('Board without v7 fields has no shared streak and no freezes', () {
      final b = Board.fromJson(board([boardUser(2, 'Sam', 'violet')]));
      expect(b.sharedStreak.isEmpty, isTrue);
      expect(b.users.single.freezes.held, 0);
      expect(b.users.single.last7.every((d) => !d.frozen && !d.away && !d.repaired), isTrue);
      expect(b.challenge, isNull);
    });

    test('Me without a schedule gets the defaults', () {
      final me = Me.fromJson(meJson());
      expect(me.schedule, const Schedule());
      expect(me.schedule.firstNotificationOffsetMin, 10);
      expect(me.schedule.workday.wake, 7 * 60);
      expect(me.schedule.workday.bed, 23 * 60);
      expect(me.protein.isEmpty, isTrue);
      expect(me.notifications.milestones, isTrue);
      expect(me.notifications.lookback, isTrue);
    });

    test('Insights without weight, activity and protein', () {
      final i = Insights.fromJson(const {});
      expect(i.weight.hasData, isFalse);
      expect(i.activity.available, isFalse);
      expect(i.protein.available, isFalse);
      expect(i.toJson().containsKey('weight'), isFalse);
    });

    test('Progress and Lookback from nothing', () {
      expect(Progress.parse(null).people, isEmpty);
      expect(Progress.parse(const {'people': 'x'}).people, isEmpty);
      final lb = Lookback.parse(const {
        'month': '2026-09',
        'people': [1, 2],
      });
      expect(lb.people, isEmpty);
      expect(lb.hasImprovements, isFalse);
    });

    test('a metric row without a key is dropped, a bad series point is ignored', () {
      final p = Progress.parse({
        'people': [
          {
            'userId': 1,
            'name': 'Nick',
            'color': 'green',
            'metrics': [
              {'title': 'no key'},
              {
                'key': 'steps',
                'title': 'Steps',
                'unit': 'steps a day',
                'goodDirection': 'sideways',
                'current': 5,
                'series': [
                  {'weekStart': '2026-10-05', 'value': 'x'},
                  3,
                  {'weekStart': '2026-10-12', 'value': 7},
                ],
              },
            ],
          },
        ],
      });
      final m = p.people.single.metrics.single;
      expect(m.goodDirection, GoodDirection.none);
      expect(m.series.map((s) => s.value), [null, 7]);
    });
  });

  group('writes', () {
    test('a free-named activity is an ActivityDraft with type other', () {
      const draft = ActivityDraft.other(
        clientOpId: 'op',
        name: 'Tennis',
        minutes: 45,
        intensity: 'moderate',
        date: '2026-10-26',
      );
      expect(draft.toJson(), {
        'kind': 'activity',
        'clientOpId': 'op',
        'date': '2026-10-26',
        'type': 'other',
        'quantity': 45,
        'unit': 'minutes',
        'name': 'Tennis',
        'intensity': 'moderate',
      });
    });

    test('an ordinary draft sends no name or intensity', () {
      const draft = ActivityDraft(clientOpId: 'op', type: 'pushups', quantity: 10, unit: 'reps');
      expect(draft.toJson().containsKey('name'), isFalse);
      expect(draft.toJson().containsKey('intensity'), isFalse);
    });

    test('an activity log keeps its name and intensity and can be undone as one', () {
      final log = LogEntry.fromJson({
        'id': 5,
        'kind': 'activity',
        'localDate': '2026-10-26',
        'loggedAt': '2026-10-26T13:00:00Z',
        'type': 'other',
        'quantity': 30,
        'unit': 'minutes',
        'name': 'Swimming',
        'intensity': 'hard',
      }) as ActivityLog;
      expect((log.name, log.intensity), ('Swimming', 'hard'));
      final again = log.toDraft('fresh').toJson();
      expect((again['name'], again['intensity'], again['type']), ('Swimming', 'hard', 'other'));
      expect(LogEntry.fromJson(log.toJson()), isA<ActivityLog>());
    });

    test('MePatch leaves the schedule out unless asked', () {
      expect(const MePatch().toJson().containsKey('schedule'), isFalse);
    });

    test('notification patches carry the two new switches and prefs write them back', () {
      expect(const NotificationPatch(milestones: false, lookback: true).toJson(), {
        'milestones': false,
        'lookback': true,
      });
      final off = NotificationPrefs.fromJson({'milestones': false, 'lookback': false});
      expect((off.milestones, off.lookback), (false, false));
      expect(off.toJson()['milestones'], isFalse);
      expect(const NotificationPrefs().toJson().containsKey('milestones'), isFalse);
    });

    test('a proposal keeps its kind, and a target proposal does not write one', () {
      final enable = GoalProposal.tryParse({
        'key': 'exercise',
        'kind': 'enable',
        'title': 'Exercise',
        'unit': 'min',
        'current': 30,
        'proposed': 30,
        'reason': 'r',
      })!;
      expect(enable.kind, 'enable');
      expect(enable.toJson()['kind'], 'enable');
      final target = GoalProposal.tryParse({'key': 'steps', 'title': 'Steps'})!;
      expect(target.kind, 'target');
      expect(target.toJson().containsKey('kind'), isFalse);
    });
  });

  group('small values', () {
    test('repair progress clamps and can be replaced', () {
      final r = Repair.tryParse({
        'date': '2026-10-26',
        'until': 'garbage',
        'progressPercent': 400,
      })!;
      expect(r.until, isNull);
      expect(r.progressPercent, 100);
      expect(r.withProgress(-5).progressPercent, 0);
    });

    test('away state lists the current span first', () {
      final a = AwayState.parse({
        'today': true,
        'current': {'id': 1, 'from': '2026-10-26', 'to': '2026-10-28', 'note': 'Flu'},
        'upcoming': [
          {'id': 2, 'from': '2026-11-02', 'to': '2026-11-03', 'note': ''},
        ],
      });
      expect(a.all.map((s) => s.id), [1, 2]);
      expect(a.isEmpty, isFalse);
    });

    test('a challenge share clamps its fraction and a challenge reads its people', () {
      final share = ChallengeShare.tryParse({
        'userId': 1,
        'name': 'Nick',
        'color': 'green',
        'target': 100,
        'progress': 250,
        'done': true,
      })!;
      expect(share.fraction, 1.0);
      expect(ChallengeShare.tryParse({'target': 0}), isNull);
      final c = Challenge.tryParse({
        'kind': 'steps',
        'title': 't',
        'target': 200,
        'progress': 10,
        'done': false,
        'endsOn': '2026-11-01',
        'people': [
          {
            'userId': 1,
            'name': 'N',
            'color': 'green',
            'target': 100,
            'progress': 10,
            'done': false,
          },
          'bad',
        ],
      })!;
      expect(c.people.length, 1);
      expect(Challenge.tryParse({'kind': 'steps', 'target': 5, 'endsOn': 'x'})!.people, isEmpty);
    });

    test('weight points need a date and a reading', () {
      final w = WeightInsights.parse({
        'smoothedKg': 82.4,
        'points': [
          {'date': '2026-10-27', 'kg': 82.4, 'smoothed': 82.4},
          {'date': '', 'kg': 80},
          {'date': '2026-10-26'},
        ],
      });
      expect(w.points.length, 1);
      expect(w.hasData, isTrue);
    });
  });
}
