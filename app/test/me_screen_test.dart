import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/food/food_screen.dart';
import 'package:newme/features/health/health_screen.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/state/me.dart';
import 'package:newme/state/session.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _template(
  String key,
  String title,
  num target,
  String unit,
  int position, {
  bool enabled = false,
}) => {
  'key': key,
  'title': title,
  'enabled': enabled,
  'target': target,
  'unit': unit,
  'targetAlt': null,
  'unitAlt': null,
  'points': 100,
  'position': position,
};

Map<String, dynamic> _me({
  bool admin = false,
  String color = 'violet',
  Map<String, int?>? targets,
}) {
  final base = meJson(admin: admin, color: color, yoga: false);
  return {
    ...base,
    'targets': {'kcal': 2200, 'protein': 150, 'carbs': null, 'fat': null, ...?targets},
    'questTemplates': [
      ...(base['questTemplates'] as List),
      _template('exercise', 'Exercise', 30, 'minutes', 6),
      _template('sleep', 'Sleep', 420, 'minutes', 7),
    ],
  };
}

StubAdapter _server({bool admin = false}) => fullServer()
  ..on('GET /api/me', StubResponse(200, _me(admin: admin)))
  ..on('PATCH /api/me', StubResponse(200, _me(admin: admin)));

TestApp _app(WidgetTester tester, StubAdapter adapter) =>
    TestApp(tester, adapter, surfaceHeight: 1600);

/// The Food tab, which holds the food targets row, with nothing burned so its card is plain.
TestApp _foodApp(WidgetTester tester, StubAdapter adapter) {
  adapter.on('GET /api/today', StubResponse(200, richTodayJson()..['food'] = restingFoodJson()));
  return _app(tester, adapter);
}

Future<void> _back(TestApp app, WidgetTester tester) async {
  await app.tap(find.byTooltip('Back'));
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the Me tab', () {
    testWidgets('shows the person header and a row for every page', (tester) async {
      final app = _app(tester, _server());
      await app.pump(const MeScreen());

      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('4 day streak'), findsOneWidget);
      expect(find.text('900 season points'), findsOneWidget);
      for (final row in ['Daily goals', 'Profile', 'Time zone', 'Apple Health']) {
        expect(find.text(row), findsOneWidget);
      }
      expect(find.text('3 of 6 on'), findsOneWidget);
      for (final moved in ['Training', 'Food targets', 'My foods']) {
        expect(find.text(moved), findsNothing, reason: '$moved moved to its own tab');
      }
      expect(find.text('America/New_York'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Pairing code'), findsNothing);
      expect(find.text('SIGN OUT OF THIS PHONE'), findsOneWidget);
      expect(find.textContaining('New Me 0.'), findsOneWidget);
    });

    testWidgets('an admin also sees the pairing code row', (tester) async {
      final app = _app(tester, _server(admin: true));
      await app.pump(const MeScreen());
      expect(find.text('Pairing code'), findsOneWidget);
    });

    testWidgets('every row is a labelled button at least 44pt tall', (tester) async {
      final handle = tester.ensureSemantics();
      final app = _app(tester, _server(admin: true));
      await app.pump(const MeScreen());

      for (final label in [
        'Daily goals, 3 of 6 on',
        'Profile, Sam, Iris',
        'Time zone, America/New_York',
        'Pairing code, Invite your partner',
      ]) {
        final row = find.bySemanticsLabel(label);
        expect(row, findsOneWidget, reason: label);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44), reason: label);
      }
      handle.dispose();
    });

    testWidgets('offline, the cached profile is shown and every edit is disabled', (tester) async {
      final adapter = _server();
      final app = _app(tester, adapter);
      await app.pump(const MeScreen(), key: UniqueKey());

      adapter.on('GET /api/me', const StubResponse.unreachable());
      await app.pump(const MeScreen(), key: UniqueKey());
      expect(find.textContaining('Offline - updated'), findsOneWidget);

      await app.tap(find.text('Daily goals'));
      expect(find.textContaining('Offline - updated'), findsOneWidget);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.onChanged == null),
        isTrue,
      );
    });

    testWidgets('offline, the food targets are shown and cannot be edited', (tester) async {
      final adapter = _server();
      final app = _foodApp(tester, adapter);
      await app.pump(const FoodScreen(), key: UniqueKey());
      await app.tap(find.text('Food targets'));
      await _back(app, tester);

      adapter.on('GET /api/me', const StubResponse.unreachable());
      await app.pump(const FoodScreen(), key: UniqueKey());
      await app.tap(find.text('Food targets'));
      final guard = find.ancestor(of: fieldWith('2200'), matching: find.byType(IgnorePointer));
      expect(tester.widget<IgnorePointer>(guard.first).ignoring, isTrue);
    });
  });

  group('daily goals', () {
    testWidgets('lists every quest including exercise and sleep, with the tomorrow note', (
      tester,
    ) async {
      final app = _app(tester, _server());
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));

      expect(find.textContaining('Changes start tomorrow'), findsOneWidget);
      for (final title in ['Steps', 'Push-ups', 'Reading', 'Yoga', 'Exercise', 'Sleep']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('8,000 steps'), findsOneWidget);
      expect(find.text('20 min or 15 pages'), findsOneWidget);
      expect(find.text('Off'), findsNWidgets(3));
    });

    testWidgets('quest switches are named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final app = _app(tester, _server());
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));

      expect(find.bySemanticsLabel('Sleep'), findsWidgets);
      expect(find.bySemanticsLabel('Exercise'), findsWidgets);
      handle.dispose();
    });

    testWidgets('Save is off until something changes, then sends only the edits', (tester) async {
      final adapter = _server();
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));

      expect(find.text('SAVE'), findsOneWidget);
      await app.tap(find.text('SAVE'));
      expect(adapter.to('PATCH /api/me'), isEmpty);

      await app.tap(find.byType(Switch).at(4));
      await app.tap(find.text('Push-ups'));
      await app.tap(find.text('Intense'));
      await app.tap(find.text('DONE'));
      expect(find.text('50 push-ups'), findsOneWidget);

      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'questTemplates': [
          {'key': 'pushups', 'target': 50},
          {'key': 'exercise', 'enabled': true},
        ],
      });
      expect(find.text('Saved. Your new goals start tomorrow.'), findsOneWidget);
      expect(find.text('Daily goals'), findsOneWidget);
    });

    testWidgets('the picker offers onboarding presets and a number of your own', (tester) async {
      final adapter = _server();
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));
      await app.tap(find.text('Steps'));

      expect(find.text('How many steps a day?'), findsOneWidget);
      for (final option in ['Casual', 'Regular', 'Serious', 'Intense']) {
        expect(find.text(option), findsOneWidget);
      }
      expect(find.text('5,000 steps'), findsOneWidget);
      expect(find.text('12,000 steps'), findsOneWidget);

      await app.enter(find.byType(TextField).first, '9500');
      await app.tap(find.text('DONE'));
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'questTemplates': [
          {'key': 'steps', 'target': 9500},
        ],
      });
    });

    testWidgets('turning a quest on by tapping it needs a goal first', (tester) async {
      final adapter = _server();
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));

      await app.tap(find.text('Sleep'));
      await app.tap(find.text('8 h'));
      await app.tap(find.text('DONE'));
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'questTemplates': [
          {'key': 'sleep', 'enabled': true, 'target': 480},
        ],
      });
    });

    testWidgets('a failed save keeps the edits and offers a retry', (tester) async {
      final adapter = _server()
        ..on('PATCH /api/me', const StubResponse(422, {'error': 'Goal is too high'}));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));

      await app.tap(find.byType(Switch).at(5));
      await app.tap(find.text('SAVE'));
      expect(find.text('Goal is too high'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch).at(5)).value, isTrue);
    });

    testWidgets('edits stay when another save lands while the page is open', (tester) async {
      final adapter = _server()..on('PATCH /api/me', StubResponse(200, _me(color: 'amber')));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Daily goals'));
      await app.tap(find.byType(Switch).at(4));

      unawaited(app.container.read(meProvider.notifier).save(const MePatch(color: 'amber')));
      await app.settle();

      expect(tester.widget<Switch>(find.byType(Switch).at(4)).value, isTrue);
    });
  });

  group('food targets', () {
    testWidgets('save only the edited fields', (tester) async {
      final adapter = _server();
      final app = _foodApp(tester, adapter);
      await app.pump(const FoodScreen());
      await app.tap(find.text('Food targets'));

      await app.enter(fieldWith('2200'), '2400');
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'targets': {'kcal': 2400},
      });
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('emptying a target sends null so the server clears it', (tester) async {
      final adapter = _server();
      final app = _foodApp(tester, adapter);
      await app.pump(const FoodScreen());
      await app.tap(find.text('Food targets'));

      await app.tap(find.byTooltip('Clear Protein (g)'));
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'targets': {'protein': null},
      });
    });

    testWidgets('an empty field that was never set is not sent', (tester) async {
      final adapter = _server();
      final app = _foodApp(tester, adapter);
      await app.pump(const FoodScreen());
      await app.tap(find.text('Food targets'));

      await app.enter(fieldWith('150'), '');
      await app.enter(find.byType(TextField).at(2), '250');
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {
        'targets': {'protein': null, 'carbs': 250},
      });
    });

    testWidgets('fields are named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final app = _foodApp(tester, _server());
      await app.pump(const FoodScreen());
      await app.tap(find.text('Food targets'));

      expect(tester.getSemantics(fieldWith('2200')).label, contains('Calories (kcal)'));
      handle.dispose();
    });

    testWidgets('typed edits survive another save', (tester) async {
      final adapter = _server()..on('PATCH /api/me', StubResponse(200, _me(color: 'amber')));
      final app = _foodApp(tester, adapter);
      await app.pump(const FoodScreen());
      await app.tap(find.text('Food targets'));
      await app.enter(fieldWith('2200'), '2400');

      unawaited(app.container.read(meProvider.notifier).save(const MePatch(color: 'amber')));
      await app.settle();

      expect(fieldWith('2400'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('a colour change saves and recolours the app', (tester) async {
      final adapter = _server()..on('PATCH /api/me', StubResponse(200, _me(color: 'amber')));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Profile'));

      await app.tap(find.text('Honey'));
      await app.tap(find.text('SAVE'));

      expect(app.body('PATCH /api/me'), {'color': 'amber'});
      expect(app.container.read(sessionProvider).session!.color, 'amber');
    });

    testWidgets('colours the other person has are shown as taken and cannot be picked', (
      tester,
    ) async {
      final adapter = _server()
        ..on(
          'GET /api/board',
          StubResponse(200, board([boardUser(2, 'Sam', 'violet'), boardUser(1, 'Ana', 'sky')])),
        );
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Profile'));

      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
      await app.tap(find.text('Sky'));
      await app.tap(find.text('SAVE'));
      expect(adapter.to('PATCH /api/me'), isEmpty);
    });

    testWidgets('a taken name shows the server message and offers a retry', (tester) async {
      final adapter = _server()
        ..on('PATCH /api/me', const StubResponse(409, {'error': 'That name is taken'}));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Profile'));

      await app.enter(find.byType(TextField).first, 'Ana');
      await app.tap(find.text('SAVE'));
      expect(find.text('That name is taken'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });

    testWidgets('saving the profile does not reload Me or rebuild the API client', (tester) async {
      final adapter = _server()..on('PATCH /api/me', StubResponse(200, _me(color: 'amber')));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      final loads = adapter.to('GET /api/me').length;
      await app.tap(find.text('Profile'));

      await app.tap(find.text('Honey'));
      await app.tap(find.text('SAVE'));

      expect(adapter.to('PATCH /api/me'), hasLength(1));
      expect(adapter.to('GET /api/me'), hasLength(loads));
    });

    testWidgets('a typed name survives another save', (tester) async {
      final adapter = _server()..on('PATCH /api/me', StubResponse(200, _me(color: 'amber')));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Profile'));
      await app.enter(find.byType(TextField).first, 'Samantha');

      unawaited(
        app.container.read(meProvider.notifier).save(const MePatch(timezone: 'Europe/London')),
      );
      await app.settle();

      expect(fieldWith('Samantha'), findsOneWidget);
    });
  });

  group('time zone', () {
    testWidgets('lists zones and shows the server verdict on free text', (tester) async {
      final adapter = _server();
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Time zone'));

      expect(find.text('This phone'), findsOneWidget);
      expect(find.text('Europe/London'), findsOneWidget);

      adapter.on(
        'PATCH /api/me',
        const StubResponse(422, {'error': 'unknown zone', 'code': 'invalid_timezone'}),
      );
      await app.enter(find.byType(TextField).first, 'Mars/Base');
      await app.tap(find.text('USE THIS ZONE'));
      expect(find.text('The server does not know "Mars/Base".'), findsOneWidget);

      adapter.on('PATCH /api/me', StubResponse(200, _me()));
      await app.tap(find.text('Europe/London'));
      expect(app.body('PATCH /api/me'), {'timezone': 'Europe/London'});
      expect(find.text('USE THIS ZONE'), findsNothing);
    });
  });

  group('apple health', () {
    testWidgets('connecting asks for access once and then shows the last sync', (tester) async {
      final adapter = _server()
        ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Apple Health'));

      expect(find.text('Not connected'), findsWidgets);
      await app.tap(find.text('CONNECT APPLE HEALTH'));
      expect(app.health.accessRequests, 1);
      expect(find.text('CONNECT APPLE HEALTH'), findsNothing);
      expect(find.text('Last sync just now'), findsOneWidget);
    });

    testWidgets('Sync now reads Health again and lists what is read', (tester) async {
      final adapter = _server()
        ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Apple Health'));
      await app.tap(find.text('CONNECT APPLE HEALTH'));

      app.health.steps = 9000;
      final reads = app.health.reads.length;
      await app.tap(find.text('SYNC NOW'));
      expect(app.health.reads.length, greaterThan(reads));

      expect(find.text('What New Me reads'), findsOneWidget);
      for (final group in ['Activity', 'Workouts', 'Sleep', 'Heart', 'Body']) {
        expect(find.text(group), findsWidgets, reason: group);
      }
      expect(find.textContaining('New Me never writes to Health'), findsOneWidget);
    });

    testWidgets('See your numbers opens the Health screen', (tester) async {
      final app = _app(tester, _server());
      await app.pump(const MeScreen());
      await app.tap(find.text('Apple Health'));
      await app.tap(find.text('CONNECT APPLE HEALTH'));

      await app.tap(find.text('See your numbers'));
      expect(find.byType(HealthScreen), findsOneWidget);
    });
  });

  group('pairing code', () {
    testWidgets('an admin can create a code, see it large and copy it', (tester) async {
      final adapter = _server(admin: true)
        ..on(
          'POST /api/invites',
          const StubResponse(201, {'code': 'K7Q2-M9XD', 'expiresAt': '2026-10-26T14:15:00Z'}),
        );
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Pairing code'));

      await app.tap(find.text('CREATE PAIRING CODE'));
      expect(find.text('K7Q2-M9XD'), findsOneWidget);
      expect(find.textContaining('Expires at'), findsOneWidget);
      expect(find.text('CREATE A NEW CODE'), findsOneWidget);

      await app.tap(find.byIcon(Icons.copy_rounded));
      expect(copied, ['K7Q2-M9XD']);
      expect(find.text('Code copied'), findsOneWidget);
    });

    testWidgets('a failure shows its message', (tester) async {
      final adapter = _server(admin: true)
        ..on('POST /api/invites', const StubResponse(403, {'error': 'Admins only'}));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('Pairing code'));
      await app.tap(find.text('CREATE PAIRING CODE'));
      expect(find.text('Admins only'), findsOneWidget);
    });
  });

  group('sign out of this phone', () {
    testWidgets('asks first, revokes the device and signs out', (tester) async {
      final adapter = _server()..on('DELETE /api/devices/me', const StubResponse(204));
      final app = _app(tester, adapter);
      await app.pump(const MeScreen());

      await app.tap(find.text('SIGN OUT OF THIS PHONE'));
      expect(find.text('Sign out of this phone?'), findsOneWidget);
      await app.tap(find.text('Cancel'));
      expect(app.container.read(sessionProvider).session, isNotNull);

      await app.tap(find.text('SIGN OUT OF THIS PHONE'));
      await app.tap(find.text('Sign out'));
      expect(app.container.read(sessionProvider).session, isNull);
      expect(adapter.to('DELETE /api/devices/me'), hasLength(1));
    });

    testWidgets('an admin is warned that only the server can bring them back', (tester) async {
      final app = _app(tester, _server(admin: true));
      await app.pump(const MeScreen());

      await app.tap(find.text('SIGN OUT OF THIS PHONE'));
      expect(find.textContaining('You are the admin'), findsOneWidget);
    });
  });
}
