import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';

import 'test_support.dart';

void main() {
  group('cheers', () {
    test('a cheer reads its sender, kind and time, and skips kinds it does not know', () {
      final cheers = parseCheers([
        {'from': 1, 'fromName': 'Nadia', 'kind': 'fire', 'at': '2026-10-26T13:00:00Z'},
        {'from': 1, 'fromName': 'Nadia', 'kind': 'confetti', 'at': '2026-10-26T13:01:00Z'},
        'junk',
      ]);
      expect(cheers, hasLength(1));
      expect(cheers.single.kind, CheerKind.fire);
      expect(cheers.single.fromName, 'Nadia');
      expect(cheers.single.at, DateTime.utc(2026, 10, 26, 13));
    });

    test('Today has no cheers when the server predates them', () {
      expect(Today.fromJson(todayJson()..remove('cheers')).cheers, isEmpty);
      expect(Today.fromJson(todayJson()..['cheers'] = 'nope').cheers, isEmpty);
    });

    test('Today keeps its cheers through a JSON round trip', () {
      final json = todayJson()
        ..['cheers'] = [
          {'from': 1, 'fromName': 'Nadia', 'kind': 'heart', 'at': '2026-10-26T13:00:00Z'},
        ];
      final again = Today.fromJson(Today.fromJson(json).toJson());
      expect(again.cheers.single.kind, CheerKind.heart);
    });
  });

  group('challenge and reward on the board', () {
    test('both are null on older servers and when malformed', () {
      expect(Board.fromJson(boardJson()..remove('challenge')).challenge, isNull);
      expect(Board.fromJson(boardJson()..['challenge'] = {'target': 0}).challenge, isNull);
      expect(Board.fromJson(boardJson()..['reward'] = 'x').reward, isNull);
    });

    test('they parse and survive a round trip', () {
      final json = boardJson()
        ..['challenge'] = {
          'kind': 'steps',
          'title': 'Walk 70,000 steps together',
          'target': 70000,
          'progress': 21000,
          'done': false,
          'endsOn': '2026-11-01',
        }
        ..['reward'] = {
          'id': 3,
          'name': 'Date night',
          'target': 2000,
          'progress': 500,
          'startedAt': '2026-10-20T10:00:00Z',
          'reachedAt': null,
          'claimedAt': null,
          'createdBy': 1,
        };
      final board = Board.fromJson(Board.fromJson(json).toJson());
      expect(board.challenge!.fraction, closeTo(0.3, 1e-9));
      expect(board.challenge!.endsOn, '2026-11-01');
      expect(board.reward!.fraction, 0.25);
      expect(board.reward!.reached, isFalse);
    });

    test('progress past the target never overfills the bar', () {
      final c = Challenge.tryParse({'target': 10, 'progress': 25, 'done': true})!;
      expect(c.fraction, 1);
    });
  });

  test('rewards list: the active one and the history, bad rows skipped', () {
    final list = RewardList.fromJson({
      'reward': null,
      'history': [
        {
          'id': 1,
          'name': 'Pizza',
          'target': 100,
          'progress': 100,
          'reachedAt': '2026-10-01T10:00:00Z',
        },
        {'id': 0, 'name': 'bad', 'target': 0},
      ],
    });
    expect(list.active, isNull);
    expect(list.history.single.reached, isTrue);
    expect(list.history.single.claimed, isFalse);
  });

  group('notifications', () {
    test('Me reads the four switches and defaults to all on', () {
      final json = {
        'user': {'id': 1, 'name': 'A', 'color': 'green', 'timezone': 'UTC', 'isAdmin': false},
        'targets': {'kcal': null, 'protein': null, 'carbs': null, 'fat': null},
        'questTemplates': <dynamic>[],
        'localToday': '2026-10-26',
        'serverNow': '2026-10-26T14:00:00Z',
      };
      expect(Me.fromJson(json).notifications.cheers, isTrue);
      json['notifications'] = {'partnerDone': false, 'cheers': true, 'challenge': false};
      final prefs = Me.fromJson(json).notifications;
      expect(
        (prefs.partnerDone, prefs.cheers, prefs.challenge, prefs.reward),
        (false, true, false, true),
      );
    });

    test('a patch sends only the switches that changed', () {
      expect(const MePatch(notifications: NotificationPatch(cheers: false)).toJson(), {
        'notifications': {'cheers': false},
      });
      expect(const MePatch().toJson().containsKey('notifications'), isFalse);
    });
  });
}
