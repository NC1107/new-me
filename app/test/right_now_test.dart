import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/recap/recap_logic.dart';
import 'package:newme/features/today/body_card.dart';
import 'package:newme/features/today/day_card.dart';
import 'package:newme/features/today/goals_card.dart';
import 'package:newme/features/today/right_now.dart';
import 'package:newme/state/together.dart';
import 'package:newme/state/together_seen.dart';
import 'package:newme/util/format.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';

// 2026-10-26 is a Monday.
final _monday9 = DateTime(2026, 10, 26, 9);
final _mondayAfternoon = DateTime(2026, 10, 26, 14);
final _tuesday9 = DateTime(2026, 10, 27, 9);
final _sunday20 = DateTime(2026, 10, 25, 20);
final _sunday18 = DateTime(2026, 10, 25, 18);

const _ready = Readiness(level: ReadinessLevel.ready);
const _cheer = Cheer(from: 1, fromName: 'Nadia', kind: CheerKind.fire);
const _proposal = GoalProposal(
  key: 'steps',
  title: 'Steps',
  unit: 'steps',
  current: 8000,
  proposed: 9000,
  reason: 'You hit it on 11 of 14 days',
);

Recap _recap({int now = 200, int before = 100, bool complete = true}) => Recap(
  week: '2026-W43',
  from: '2026-10-19',
  to: '2026-10-25',
  complete: complete,
  people: const [],
  pair: RecapPair(
    thisWeek: RecapStats(points: now),
    previous: RecapStats(points: before),
  ),
);

Quest _q(String key, {int points = 100, int base = 0, bool done = false}) => Quest.fromJson(
  quest(key, key, {'points': points, 'basePoints': base, 'done': done, 'target': 10}),
);

DayScore _day({int base = 100, int max = 400, bool counted = false}) => DayScore.fromJson(
  dayJson(points: base + 20, percent: base * 100 ~/ max, counted: counted)
    ..['basePoints'] = base
    ..['maxBase'] = max,
);

void main() {
  group('pickRightNow chooses the one card for the moment', () {
    test('nothing to show is nothing', () {
      expect(pickRightNow(now: _tuesday9), isNull);
    });

    test('readiness shows in the morning and goes at noon', () {
      expect(pickRightNow(now: _tuesday9, readiness: _ready), isA<RightNowReadiness>());
      expect(
        pickRightNow(now: DateTime(2026, 10, 27, 11, 59), readiness: _ready),
        isA<RightNowReadiness>(),
      );
      expect(pickRightNow(now: DateTime(2026, 10, 27, 12), readiness: _ready), isNull);
    });

    test('a dismissed readiness gives way', () {
      expect(pickRightNow(now: _tuesday9, readiness: _ready, readinessDismissed: true), isNull);
    });

    test('a received cheer beats readiness', () {
      final picked = pickRightNow(now: _tuesday9, readiness: _ready, cheers: [_cheer]);
      expect(picked, isA<RightNowCheers>());
      expect((picked! as RightNowCheers).cheers, [_cheer]);
    });

    test('Monday goals come after the morning readiness and stay all day', () {
      expect(
        pickRightNow(now: _monday9, readiness: _ready, proposals: [_proposal]),
        isA<RightNowReadiness>(),
      );
      expect(
        pickRightNow(
          now: _monday9,
          readiness: _ready,
          readinessDismissed: true,
          proposals: [_proposal],
        ),
        isA<RightNowGoals>(),
      );
      expect(
        pickRightNow(now: _mondayAfternoon, readiness: _ready, proposals: [_proposal]),
        isA<RightNowGoals>(),
      );
    });

    test('proposals are a Monday card only', () {
      expect(pickRightNow(now: _tuesday9, proposals: [_proposal]), isNull);
    });

    test('the recap shows Sunday from 19:00 and on Monday, behind goals', () {
      expect(pickRightNow(now: _sunday20, recap: _recap()), isA<RightNowRecap>());
      expect(pickRightNow(now: _sunday18, recap: _recap()), isNull);
      expect(pickRightNow(now: _tuesday9, recap: _recap()), isNull);
      expect(pickRightNow(now: _mondayAfternoon, recap: _recap()), isA<RightNowRecap>());
      expect(
        pickRightNow(now: _mondayAfternoon, recap: _recap(), proposals: [_proposal]),
        isA<RightNowGoals>(),
      );
    });

    test('a dismissed recap gives way, and so does everything on a quiet day', () {
      expect(pickRightNow(now: _sunday20, recap: _recap(), recapDismissed: true), isNull);
    });

    test('the cheer outranks everything on a Monday morning', () {
      final picked = pickRightNow(
        now: _monday9,
        cheers: [_cheer],
        readiness: _ready,
        proposals: [_proposal],
        recap: _recap(),
      );
      expect(picked, isA<RightNowCheers>());
    });
  });

  group('the day card sentence', () {
    test('a fresh day with no streak starts one instead of threatening it', () {
      final s = dayCardSentence(_day(base: 0), const Streak(current: 0, restAvailable: false), [
        _q('steps'),
      ]);
      expect(s, 'Reach 100% today to start your streak.');
    });

    test('a running streak is kept', () {
      final s = dayCardSentence(_day(base: 0), const Streak(current: 3, restAvailable: false), [
        _q('steps'),
      ]);
      expect(s, 'Reach 100% to keep your streak going.');
    });

    test('one quest away reads as one more', () {
      // 280 of 400 is the line; 250 earned, and an open quest worth 100 with 30 earned can close it.
      final day = _day(base: 250);
      final quests = [_q('steps', base: 30), _q('reading', done: true, base: 100)];
      expect(oneQuestAway(day, quests), isTrue);
      expect(
        dayCardSentence(day, const Streak(current: 3, restAvailable: true), quests),
        'One more and you count today.',
      );
      expect(
        dayCardSentence(day, const Streak(current: 0, restAvailable: false), quests),
        'One more and you count today.',
      );
    });

    test('two quests away is not one more', () {
      expect(oneQuestAway(_day(base: 100), [_q('steps'), _q('reading')]), isFalse);
    });

    test('a counted day is never one away', () {
      expect(oneQuestAway(_day(base: 300, counted: true), [_q('steps')]), isFalse);
    });
  });

  group('copy helpers', () {
    test('doneByLabel names the workout and its minutes', () {
      expect(
        doneByLabel(const DoneBy(kind: 'workout', type: 'strength', minutes: 42)),
        'Done by your Strength workout, 42 min',
      );
      expect(
        doneByLabel(const DoneBy(kind: 'workout', type: 'hiit', minutes: 15)),
        'Done by your HIIT workout, 15 min',
      );
      expect(
        doneByLabel(const DoneBy(kind: 'workout', type: 'yoga', minutes: 30)),
        'Done by your Yoga workout, 30 min',
      );
    });

    test('agoLabel and the listening note', () {
      final now = DateTime.utc(2026, 10, 27, 12);
      expect(agoLabel(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(agoLabel(now.subtract(const Duration(minutes: 3)), now), '3 min ago');
      expect(agoLabel(now.subtract(const Duration(hours: 2)), now), '2 h ago');
      expect(agoLabel(now.subtract(const Duration(days: 2)), now), '2 d ago');
      expect(
        listeningSyncedLabel(now.subtract(const Duration(minutes: 3)), now),
        'Listening synced 3 min ago',
      );
    });

    test('Season 0 is the Preseason', () {
      expect(seasonLabel('Season 0'), 'Preseason');
      expect(seasonLabel('Season 1'), 'Season 1');
    });

    test('proposals read in the unit people think in', () {
      expect(proposalValue(_proposal, 9000), '9,000 steps');
      const sleep = GoalProposal(
        key: 'sleep',
        title: 'Sleep',
        unit: 'minutes',
        current: 480,
        proposed: 450,
        reason: 'r',
      );
      expect(proposalValue(sleep, 450), '7 h 30 min');
    });

    test('the Body row summarises sleep and workouts, or points at Insights', () {
      final health = HealthStatus.fromJson({
        'stepsEverSynced': true,
        'metrics': {'sleep_minutes': 432, 'weight_kg': 80},
      });
      expect(bodySummary(health, null), 'Slept 7 h 12 min');
      expect(
        bodySummary(HealthStatus.fromJson(const {'stepsEverSynced': true}), null),
        'Steps, sleep and workouts',
      );
    });
  });

  group('recap logic', () {
    test('the headline reads the same for a good week and a slow one', () {
      expect(
        recapHeadline(_recap(now: 200, before: 100)),
        contains('100 more than the week before'),
      );
      expect(
        recapHeadline(_recap(now: 100, before: 200)),
        contains('100 fewer than the week before'),
      );
      expect(recapHeadline(_recap(now: 100, before: 0)), 'Together you earned 100 points.');
      expect(
        recapHeadline(_recap(now: 150, complete: false, before: 0)),
        'Together you have 150 points so far.',
      );
    });

    test('signed changes carry a sign and a unit', () {
      expect(signedChange(1200), '+1,200');
      expect(signedChange(-30, unit: 'min'), '-30 min');
      expect(signedChange(0), 'Same');
    });

    test('rows compare a finished week and show last week for a running one', () {
      const now = RecapStats(points: 200, steps: 50000, sleepAvgMin: 450, sleepNights: 5);
      const before = RecapStats(points: 150, steps: 60000, sleepAvgMin: 420, sleepNights: 6);
      final done = recapRows(now, before);
      expect(done.first.change, '+50');
      expect(done.first.direction, 1);
      expect(done[2].change, '-10,000');
      expect(done[2].direction, -1);
      expect(done[3].change, '+30 min');

      final running = recapRows(now, before, complete: false);
      expect(running.every((r) => r.change == null), isTrue);
      expect(running.first.before, '150');
      expect(running[3].before, '7 h');
    });

    test('sleep is not compared without nights on both sides', () {
      final rows = recapRows(
        const RecapStats(),
        const RecapStats(sleepAvgMin: 400, sleepNights: 3),
      );
      expect(rows[3].value, 'None recorded');
      expect(rows[3].change, isNull);
    });
  });

  group('the Us badge', () {
    final today = Today.fromJson(richTodayJson());
    const memory = CheerMemoryState(loaded: true);
    const seen = TogetherSeenState(loaded: true);

    bool badge({
      List<Cheer> cheers = const [],
      Board? board,
      CheerMemoryState cheerMemory = memory,
      TogetherSeenState seenState = seen,
    }) => usNeedsAttention(
      cheers: cheers,
      cheerDate: today.localToday,
      cheerMemory: cheerMemory,
      board: board,
      seen: seenState,
    );

    Board boardWith({Map<String, dynamic>? challenge, Map<String, dynamic>? reward}) =>
        Board.fromJson({
          ...board([boardUser(1, 'Nick', 'green')]),
          'challenge': challenge,
          'reward': reward,
        });

    Map<String, dynamic> challenge({bool done = true}) => {
      'kind': 'steps',
      'title': 'Walk',
      'target': 100,
      'progress': done ? 100 : 5,
      'done': done,
      'endsOn': '2026-11-01',
    };

    test('a quiet board has none', () {
      expect(badge(board: boardWith()), isFalse);
    });

    test('an unseen cheer lights it and a dismissed one does not', () {
      expect(badge(cheers: [_cheer]), isTrue);
      expect(
        badge(
          cheers: [_cheer],
          cheerMemory: CheerMemoryState(
            loaded: true,
            dismissed: {'${today.localToday}|${_cheer.from}|${_cheer.kind.name}'},
          ),
        ),
        isFalse,
      );
    });

    test('a completed challenge lights it until its celebration played', () {
      expect(badge(board: boardWith(challenge: challenge())), isTrue);
      expect(badge(board: boardWith(challenge: challenge(done: false))), isFalse);
      expect(
        badge(
          board: boardWith(challenge: challenge()),
          seenState: const TogetherSeenState(loaded: true, challengeEndsOn: '2026-11-01'),
        ),
        isFalse,
      );
    });

    test('a reached reward lights it until celebrated or claimed', () {
      final reward = {
        'id': 7,
        'name': 'Date night',
        'target': 100,
        'progress': 100,
        'reachedAt': '2026-10-26T10:00:00Z',
      };
      expect(badge(board: boardWith(reward: reward)), isTrue);
      expect(
        badge(
          board: boardWith(reward: reward),
          seenState: const TogetherSeenState(loaded: true, rewardId: 7),
        ),
        isFalse,
      );
      expect(
        badge(board: boardWith(reward: {...reward, 'claimedAt': '2026-10-26T11:00:00Z'})),
        isFalse,
      );
    });

    test('nothing lights before the memory has loaded', () {
      expect(
        badge(
          board: boardWith(challenge: challenge()),
          seenState: const TogetherSeenState(),
        ),
        isFalse,
      );
    });
  });
}
