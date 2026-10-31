import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/daily_reps_page.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _option(
  String key,
  String name,
  String noun,
  String singular, {
  Map<String, dynamic>? latestMax,
  bool available = true,
  String? needs,
}) => {
  'key': key,
  'name': name,
  'noun': noun,
  'singular': singular,
  'hint': 'How to do $noun.',
  'available': available,
  'needs': ?needs,
  'latestMax': latestMax,
};

Map<String, dynamic> _state({String exercise = 'push_up', int target = 30, String? day}) => {
  'exercise': exercise,
  'target': target,
  'enabled': true,
  'dayExercise': day ?? exercise,
  'sets': 3,
  'exercises': [
    _option('knee_push_up', 'Knee push-ups', 'knee push-ups', 'knee push-up'),
    _option('push_up', 'Push-ups', 'push-ups', 'push-up'),
    _option(
      'air_squat',
      'Squats',
      'squats',
      'squat',
      latestMax: {'date': '2026-10-20', 'reps': 20},
    ),
    _option('pull_up', 'Pull-ups', 'pull-ups', 'pull-up', available: false, needs: 'pullup_bar'),
  ],
  'sources': [
    {'key': 'zourdos2016', 'text': 'Zourdos et al., J Strength Cond Res 2016'},
  ],
};

Map<String, dynamic> _preview(String exercise, int max, int perSet, int low, int high) => {
  'exercise': exercise,
  'max': max,
  'sets': 3,
  'repsPerSet': perSet,
  'low': low,
  'high': high,
  'daily': perSet * 3,
  'formula': 'unused',
  'sources': [
    {'key': 'zourdos2016', 'text': 'Zourdos et al., J Strength Cond Res 2016'},
  ],
};

StubAdapter _server() => fullServer()
  ..on('GET /api/daily-reps', StubResponse(200, _state()))
  ..on('GET /api/daily-reps/preview', StubResponse(200, _preview('air_squat', 20, 15, 14, 16)))
  ..on('PUT /api/daily-reps', StubResponse(200, _state(exercise: 'air_squat', target: 45)));

class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) => Center(
    child: ElevatedButton(
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const DailyRepsPage())),
      child: const Text('Open'),
    ),
  );
}

Future<TestApp> _open(WidgetTester tester, StubAdapter adapter) async {
  final app = TestApp(tester, adapter);
  await app.pump(const _Opener());
  await app.tap(find.text('Open'));
  await app.settle(24);
  return app;
}

Finder _save() => find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Save');

bool _saveEnabled(WidgetTester tester) => tester.widget<ChunkyButton>(_save()).onPressed != null;

Future<void> _type(TestApp app, String text) async {
  await app.tester.enterText(find.byType(TextField).first, text);
  await app.settle(24);
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('lists the exercises, with the pull-up closed until the bar is set', (tester) async {
    await _open(tester, _server());
    expect(find.text('Daily reps'), findsOneWidget);
    expect(find.text('Push-ups (current)'), findsOneWidget);
    for (final name in ['Knee push-ups', 'Squats', 'Pull-ups']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('Needs a pull-up bar'), findsOneWidget);
  });

  testWidgets('picking squats and typing a max shows the derived target before saving', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter);
    expect(_saveEnabled(tester), isFalse);

    await app.tap(find.text('Squats'));
    // The squat max already on record fills the field.
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '20');
    await app.settle(24);

    expect(find.text('3 sets of 15 squats'), findsOneWidget);
    expect(find.textContaining('45 a day'), findsOneWidget);
    expect(find.textContaining('14 to 16 a set'), findsOneWidget);
    expect(find.textContaining('Zourdos'), findsOneWidget);
    expect(find.text('Test now'), findsOneWidget);
    final preview = adapter.to('GET /api/daily-reps/preview').last;
    expect(preview.queryParameters, {'exercise': 'air_squat', 'max': 20});
    expect(adapter.to('PUT /api/daily-reps'), isEmpty);

    await app.tap(_save());
    expect(app.body('PUT /api/daily-reps'), {'exercise': 'air_squat', 'max': 20});
  });

  testWidgets('a person who does not know their max picks a starting set, not a default', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter);
    await app.tap(find.text('Knee push-ups'));
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);

    await app.tap(find.text('Not sure yet'));
    expect(find.textContaining('We do not pick a starting number for you'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    expect(_saveEnabled(tester), isFalse);
    expect(find.text('Test now'), findsOneWidget);

    await _type(app, '4');
    expect(find.text('3 sets of 4 knee push-ups'), findsOneWidget);
    expect(find.textContaining('12 a day'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);

    await app.tap(_save());
    expect(app.body('PUT /api/daily-reps'), {'exercise': 'knee_push_up', 'repsPerSet': 4});
  });

  testWidgets('a max above the limit is refused before it is sent', (tester) async {
    final app = await _open(tester, _server());
    await app.tap(find.text('Squats'));
    await _type(app, '$kMaxRepsMax');
    expect(_saveEnabled(tester), isTrue);
    await _type(app, '${kMaxRepsMax + 1}');
    expect(find.text('At most $kMaxRepsMax'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('a change that waits for tomorrow says so', (tester) async {
    final adapter = _server()
      ..on(
        'PUT /api/daily-reps',
        StubResponse(200, _state(exercise: 'air_squat', target: 45, day: 'push_up')),
      );
    final app = await _open(tester, adapter);
    await app.tap(find.text('Squats'));
    await app.settle(24);
    await app.tap(_save());
    expect(find.textContaining('Today still counts push-ups'), findsOneWidget);
  });

  group('titles follow the exercise', () {
    Quest quest(Map<String, dynamic> extra) => Quest.fromJson({
      'key': 'pushups',
      'title': 'Squats',
      'unit': 'reps',
      'target': 45,
      'actual': 0,
      'points': 100,
      'basePoints': 0,
      'bonusPoints': 0,
      'done': false,
      ...extra,
    });

    test('the Today card names the exercise in its progress line', () {
      expect(questProgress(quest({'exercise': 'air_squat'})), 'A strength session or 45 squats');
      expect(
        questProgress(quest({'exercise': 'air_squat', 'actual': 12})),
        '12 of 45 squats, or a strength workout',
      );
      expect(questTitle(quest({'exercise': 'air_squat'})), 'Get stronger');
    });

    test('a quest without an exercise still reads as push-ups', () {
      expect(questProgress(quest({'target': 30})), 'A strength session or 30 push-ups');
    });
  });

  testWidgets('the log sheet logs the exercise the day counts', (tester) async {
    final today = richTodayJson();
    for (final q in today['quests'] as List) {
      if ((q as Map<String, dynamic>)['key'] == 'pushups') {
        q['exercise'] = 'air_squat';
        q['title'] = 'Squats';
      }
    }
    final adapter = fullServer()
      ..on('GET /api/today', StubResponse(200, today))
      ..on('POST /api/logs', StubResponse(201, logResultJson()));
    final app = TestApp(tester, adapter);
    await app.pump(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showLogSheet(context, kind: LogKind.pushups),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await app.tap(find.text('Open'));
    await app.settle(24);
    expect(find.text('Log squats'), findsOneWidget);
    await app.tap(find.text('SAVE'));
    expect(adapter.to('POST /api/logs'), hasLength(1));
    expect(app.body('POST /api/logs')['type'], 'pushups');
  });
}
