import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/main.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/timezone.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_scheduler.dart';
import 'fixtures.dart';
import 'test_support.dart';

const _info = {'name': 'Us', 'initialized': true, 'joinOpen': true, 'minClientVersion': '0.1.0'};

const _nick = {'id': 1, 'name': 'Nick', 'color': 'green'};

const _code = 'ABCD-EFGH-JKLM-NPQR';

class _App {
  _App(this.tester, this.adapter);

  final WidgetTester tester;
  final StubAdapter adapter;
  final health = FakeHealthSource();
  final reminders = FakeReminderScheduler();
  final storage = FakeStorage();

  Future<void> launch({SessionController Function()? session}) async {
    storage.install();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
          healthSourceProvider.overrideWithValue(health),
          reminderSchedulerProvider.overrideWithValue(reminders),
          if (session != null) sessionProvider.overrideWith(session),
        ],
        child: const NewMeApp(),
      ),
    );
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text));

  /// Button labels are shown in capitals.
  Future<void> tapButton(String label) => tap(find.text(label.toUpperCase()));

  Future<void> enter(String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
  }

  bool enabled(String label) {
    final button = tester.widget<ChunkyButton>(
      find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label),
    );
    return button.onPressed != null;
  }

  Map<String, dynamic> lastBody(String route) =>
      (adapter.to(route).last.data as Map).cast<String, dynamic>();

  /// From a fresh first run to the units step: Get started, a name, the default colour.
  Future<void> joinFirst() async {
    await launch();
    await tapButton('Get started');
    await enter('Ana');
    await tapButton('Continue');
    await tapButton('Continue');
  }

  /// From the units step to the schedule: keeps the units, answers Health, skips About you.
  Future<void> unitsToSchedule({bool connect = false}) async {
    await tapButton('Continue');
    await tapButton(connect ? 'Connect Apple Health' : 'Not now');
    await tapButton('Skip for now');
    await tapButton('Skip');
  }

  /// From the schedule to reminders: the default times, [focus], and the daily goals as shown.
  Future<void> scheduleToReminders(String focus) async {
    await tapButton('Use 7:00 AM and 11:00 PM');
    await tapText(focus);
    await tapButton('Continue');
    await tapButton('Use these');
  }

  Future<void> expectSignedIn() async {
    expect(find.text('Today'), findsWidgets);
  }
}

/// The profile the fake server holds: PATCHes change its units, and reads return them.
class _FakeMe {
  /// Null until chosen, like a new profile on the server.
  String? units;

  StubResponse _answer() {
    final me = meJson();
    return StubResponse(200, {
      ...me,
      'user': {...(me['user'] as Map<String, dynamic>), 'units': units},
    });
  }

  StubResponse patch(RequestOptions req) {
    final body = req.data;
    if (body is Map && body['units'] is String) units = body['units'] as String;
    return _answer();
  }

  StubResponse get(RequestOptions _) => _answer();
}

Map<String, dynamic> _targets(String name) =>
    (jsonDecode(File('test/contract_v8/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

StubAdapter _server({Map<String, dynamic> info = _info}) {
  final me = _FakeMe();
  return StubAdapter()
    ..on('GET /api/server-info', StubResponse(200, info))
    ..routes['GET /api/me'] = me.get
    ..on(
      'POST /api/join',
      const StubResponse(201, {
        'user': {
          'id': 2,
          'name': 'Ana',
          'color': 'sky',
          'timezone': 'America/New_York',
          'isAdmin': false,
        },
        'token': 'new-token',
      }),
    )
    ..routes['PATCH /api/me'] = me.patch
    ..on(
      'POST /api/invites/check',
      const StubResponse(200, {
        'valid': true,
        'users': [_nick],
        'canJoinNew': true,
      }),
    );
}

void main() {
  testWidgets('first join walks name, colour, units, Health, About you, schedule, focus and daily '
      'goals, and lands in the app', (tester) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final app = _App(tester, adapter);
    await app.launch();

    expect(adapter.to('GET /api/server-info').single.uri.host, 'new-me.npc-server.top');
    expect(find.byType(TextField), findsNothing, reason: 'no server address in the normal flow');
    expect(find.text('GET STARTED'), findsOneWidget);
    expect(find.text('I HAVE AN INVITE CODE'), findsNothing, reason: 'nobody to invite from yet');
    await app.tapButton('Get started');

    expect(find.text('What should we call you?'), findsOneWidget);
    expect(app.enabled('Continue'), isFalse);
    await app.enter('Ana');
    await app.tapButton('Continue');

    expect(find.text('Pick your color'), findsOneWidget);
    await app.tapText('Sky');
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/join'), {
      'name': 'Ana',
      'color': 'sky',
      'timezone': 'America/New_York',
    });
    expect(app.storage.values[kSessionKey], contains('new-token'));

    expect(find.text('Which units do you use?'), findsOneWidget);
    await app.tapText('Pounds and feet');
    await app.tapButton('Continue');
    expect(app.lastBody('PATCH /api/me'), {'units': 'imperial'});

    expect(find.text('Connect Apple Health'), findsWidgets);
    await app.tapButton('Not now');
    expect(app.health.accessRequests, 0);
    expect(find.text('About you'), findsOneWidget);
    await app.tapButton('Skip for now');
    expect(find.text('What is your weight goal?'), findsOneWidget);
    await app.tapButton('Skip');

    expect(find.text('When do you usually wake up?'), findsOneWidget);
    await app.tapButton('Use 7:00 AM and 11:00 PM');
    expect(find.text('What do you want to work on?'), findsOneWidget);
    expect(app.enabled('Continue'), isFalse, reason: 'one focus is required');
    await app.tapText('Move more');
    await app.tapText('Sleep better');
    await app.tapButton('Continue');

    expect(find.text('Your daily goals'), findsOneWidget);
    expect(find.text('How many steps a day?'), findsNothing, reason: 'no number screens any more');
    expect(find.text('7,000 steps'), findsOneWidget);
    await app.tap(find.bySemanticsLabel('More Steps'));
    expect(find.text('7,500 steps'), findsOneWidget);
    expect(adapter.to('PATCH /api/me'), hasLength(1), reason: 'only the units so far');
    await app.tapButton('Use these');

    final patch = app.lastBody('PATCH /api/me');
    final templates = {for (final t in patch['questTemplates'] as List) (t as Map)['key']: t};
    expect(templates['steps'], {'key': 'steps', 'enabled': true, 'target': 7500});
    expect(templates['sleep'], {'key': 'sleep', 'enabled': true, 'target': 450});
    expect(templates['exercise'], {'key': 'exercise', 'enabled': false});
    expect(templates['pushups'], {'key': 'pushups', 'enabled': false});
    expect(patch.containsKey('targets'), isFalse);

    expect(find.text('Want a nudge in the evening?'), findsOneWidget);
    await app.tapButton('Not now');
    expect(app.reminders.permissionRequests, 0, reason: 'NOT NOW never asks the system');
    expect(app.reminders.pending, isEmpty);
    expect(find.text("You're in, Ana!"), findsOneWidget);
    expect(find.text('Day 1 starts now.'), findsOneWidget);
    await app.tapButton("Let's go");
    await app.expectSignedIn();
  });

  testWidgets('daily goals come from the formulas once the answers allow, with food targets', (
    tester,
  ) async {
    final adapter = _server(info: {..._info, 'initialized': false})
      ..on('GET /api/targets', StubResponse(200, _targets('targets')))
      ..on(
        'POST /api/targets/apply',
        StubResponse(200, {
          ...meJson(),
          'applied': ['fat', 'carbs'],
        }),
      );
    final app = _App(tester, adapter);
    await app.joinFirst();
    await app.unitsToSchedule();
    await app.tapButton('Use 7:00 AM and 11:00 PM');
    await app.tapText('Move more');
    await app.tapText('Eat well');
    await app.tapButton('Continue');

    expect(find.text('7,000 steps'), findsOneWidget);
    expect(find.textContaining('Paluch'), findsOneWidget);
    expect(find.text('165 g'), findsOneWidget, reason: 'protein per kilogram for the goal');
    expect(find.text('2,350 kcal'), findsOneWidget);
    expect(find.text('3 meals'), findsOneWidget);
    expect(
      find.textContaining('A starting point'),
      findsOneWidget,
      reason: 'meals have no formula',
    );
    await app.tapButton('Use these');

    final patch = app.lastBody('PATCH /api/me');
    expect(patch['targets'], {'kcal': 2350});
    final templates = {for (final t in patch['questTemplates'] as List) (t as Map)['key']: t};
    expect(templates['protein'], {'key': 'protein', 'enabled': true, 'target': 165});
    expect(templates['meals_logged'], {'key': 'meals_logged', 'enabled': true, 'target': 3});
    expect(app.lastBody('POST /api/targets/apply'), {
      'keys': ['fat', 'carbs'],
    });
    expect(find.text('Want a nudge in the evening?'), findsOneWidget);
  });

  testWidgets('Get stronger asks for no number and reads as more than push-ups', (tester) async {
    final app = _App(tester, _server(info: {..._info, 'initialized': false}));
    await app.joinFirst();
    await app.unitsToSchedule();
    await app.tapButton('Use 7:00 AM and 11:00 PM');
    expect(find.text('A strength workout, a training session or push-ups'), findsOneWidget);
    await app.tapText('Get stronger');
    await app.tapButton('Continue');
    expect(find.text('Push-ups, or a strength workout'), findsOneWidget);
    expect(find.text('20 push-ups'), findsOneWidget);
  });

  testWidgets('a code leads to "I am new", with taken colours disabled, then connects Health', (
    tester,
  ) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    await app.tapButton('Join with a code');
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(find.text('You were signed out. Enter a code to come back.'), findsNothing);
    expect(app.enabled('Continue'), isFalse);
    await app.enter(' abcd efgh jklm npqr ');
    expect(find.text('ABCD'), findsOneWidget, reason: 'typed codes fill the boxes');
    expect(find.text('NPQR'), findsOneWidget);
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/invites/check'), {'code': _code});

    expect(find.text('Have you used New Me before?'), findsOneWidget);
    await app.tapText('I am new here');
    await app.enter('Ana');
    await app.tapButton('Continue');

    expect(find.bySemanticsLabel('Fern, taken'), findsOneWidget);
    await app.tapText('Fern');
    expect(app.enabled('Continue'), isTrue, reason: 'a taken colour cannot be picked');
    await app.tapText('Iris');
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/join'), {
      'code': _code,
      'name': 'Ana',
      'color': 'violet',
      'timezone': 'America/New_York',
    });

    await app.unitsToSchedule(connect: true);
    expect(app.health.accessRequests, 1);
    await app.scheduleToReminders('Read more');

    expect(find.text('Want a nudge in the evening?'), findsOneWidget);
    expect(find.text('8:00 PM'), findsOneWidget);
    await app.tapText('9:00 PM');
    expect(app.reminders.permissionRequests, 0, reason: 'picking a time asks for nothing');
    await app.tapButton('Allow');
    expect(app.reminders.permissionRequests, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('reminderMinutes'), 21 * 60);
    expect(prefs.getBool('remindersEnabled'), isTrue);
    expect(find.text("You're in, Ana!"), findsOneWidget);
  });

  testWidgets('a returning person picks themselves and only the code and id are sent', (
    tester,
  ) async {
    final adapter = _server()
      ..on(
        'POST /api/join',
        const StubResponse(201, {
          'user': {
            'id': 1,
            'name': 'Nick',
            'color': 'amber',
            'timezone': 'America/New_York',
            'isAdmin': true,
          },
          'token': 'repaired-token',
        }),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');
    await app.tapText('I have been here before');

    expect(find.text('Who are you?'), findsOneWidget);
    expect(app.enabled('Continue'), isFalse);
    await app.tapText('Nick');
    await app.tapButton('Continue');

    expect(app.lastBody('POST /api/join'), {'code': _code, 'userId': 1});
    expect(adapter.to('PATCH /api/me'), isEmpty, reason: 'a returning person keeps their goals');
    expect(find.text('What do you want to work on?'), findsNothing);
    final button = tester.widget<Theme>(find.byType(Theme).first);
    expect(
      button.data.extension<AccentPalette>()!.id,
      'amber',
      reason: 'the health step already wears the returning person colour',
    );
    await app.tapButton('Not now');
    await app.tapButton('Not now');
    expect(find.text('Welcome back, Nick!'), findsOneWidget);
    await app.tapButton("Let's go");
    await app.expectSignedIn();
  });

  testWidgets('a code the server does not accept explains itself and stays editable', (
    tester,
  ) async {
    final adapter = _server()
      ..on(
        'POST /api/invites/check',
        const StubResponse(200, {'valid': false, 'users': <Object>[], 'canJoinNew': false}),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');

    expect(find.text('That code did not work. Ask for a fresh one.'), findsOneWidget);
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(app.enabled('Continue'), isTrue);
  });

  testWidgets('a full server offers only the people already on it', (tester) async {
    final adapter = _server()
      ..on(
        'POST /api/invites/check',
        const StubResponse(200, {
          'valid': true,
          'users': [_nick],
          'canJoinNew': false,
        }),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Nick'), findsOneWidget);
    expect(find.text('I am new here'), findsNothing);
  });

  testWidgets('an unreachable server shows a sad mascot and recovers with Try again', (
    tester,
  ) async {
    var up = false;
    final adapter = _server()
      ..routes['GET /api/server-info'] = (request) =>
          up ? const StubResponse(200, _info) : const StubResponse.unreachable();
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('New Me cannot be reached right now'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<Mascot>(find.byType(Mascot)).state, MascotState.sad);

    up = true;
    await app.tapButton('Try again');
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
  });

  testWidgets('holding the mascot for three seconds opens the server override', (tester) async {
    final adapter = _server()..on('GET /api/server-info', const StubResponse(404, {'error': 'x'}));
    final app = _App(tester, adapter);
    await app.launch();
    expect(find.text('That address does not look like a New Me server.'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(Mascot)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Server'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await app.settle();
    expect(find.text('Server'), findsOneWidget);

    adapter.on('GET /api/server-info', const StubResponse(200, _info));
    await tester.enterText(find.byType(TextField), 'http://192.168.1.5:8080/');
    await app.tapButton('Connect');

    expect(
      adapter.to('GET /api/server-info').last.uri.toString(),
      'http://192.168.1.5:8080/api/server-info',
    );
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
  });

  testWidgets('a server that wants a newer client says so', (tester) async {
    final adapter = _server(info: {..._info, 'minClientVersion': '9.0.0'});
    final app = _App(tester, adapter);
    await app.launch();
    expect(find.text('Time to update'), findsOneWidget);

    adapter.on('GET /api/server-info', const StubResponse(426, {'error': 'old'}));
    await app.tapButton('Try again');
    expect(find.text('Time to update'), findsOneWidget);
  });

  Future<void> relaunchWith(
    WidgetTester tester,
    _App first,
    StubAdapter adapter, {
    FakeReminderScheduler? reminders,
  }) async {
    await tester.pumpWidget(const SizedBox());
    final relaunch = _App(tester, adapter)..storage.values.addAll(first.storage.values);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
          healthSourceProvider.overrideWithValue(relaunch.health),
          reminderSchedulerProvider.overrideWithValue(reminders ?? relaunch.reminders),
        ],
        child: const NewMeApp(),
      ),
    );
    await relaunch.settle();
  }

  testWidgets('leaving after the profile exists resumes at the first unanswered step', (
    tester,
  ) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final first = _App(tester, adapter);
    await first.joinFirst();
    await first.unitsToSchedule();
    await first.tapButton('Use 7:00 AM and 11:00 PM');
    await first.tapText('Read more');
    await first.tapButton('Continue');
    expect(find.text('Your daily goals'), findsOneWidget);

    await relaunchWith(tester, first, adapter);
    expect(find.text('Your daily goals'), findsOneWidget);
    expect(find.text('Today'), findsNothing, reason: 'the app does not open until onboarding ends');
  });

  testWidgets('leaving at the reminder step resumes there, and Allow honours a denial', (
    tester,
  ) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final first = _App(tester, adapter);
    await first.joinFirst();
    await first.unitsToSchedule();
    await first.scheduleToReminders('Read more');
    expect(find.text('Want a nudge in the evening?'), findsOneWidget);

    final denying = FakeReminderScheduler(grantsOnRequest: false);
    await relaunchWith(tester, first, adapter, reminders: denying);
    expect(find.text('Want a nudge in the evening?'), findsOneWidget);
    await first.tester.pump();
    await tester.ensureVisible(find.text('ALLOW'));
    await tester.tap(find.text('ALLOW'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(denying.permissionRequests, 1);
    expect(denying.pending, isEmpty, reason: 'nothing is scheduled without permission');
    expect(
      find.text("You're in, Ana!"),
      findsOneWidget,
      reason: 'a denial does not block the flow',
    );
  });

  group('the About you steps', () {
    StubAdapter aboutServer({String targets = 'targets_missing'}) =>
        _server(info: {..._info, 'initialized': false})
          ..on('GET /api/targets', StubResponse(200, _targets(targets)))
          ..on('PUT /api/health/daily', const StubResponse(200, {'days': []}));

    /// To the one-screen About you, choosing [units] and answering Health.
    Future<_App> toAbout(
      WidgetTester tester,
      StubAdapter adapter, {
      String units = 'Pounds and feet',
      bool connect = false,
    }) async {
      final app = _App(tester, adapter);
      await app.joinFirst();
      await app.tapText(units);
      await app.tapButton('Continue');
      await app.tapButton(connect ? 'Connect Apple Health' : 'Not now');
      expect(find.text('About you'), findsOneWidget);
      return app;
    }

    /// Fields are found by their hint, which their accessible name also carries.
    Future<void> enterField(WidgetTester tester, String hint, String text) async {
      await tester.enterText(find.widgetWithText(TextField, hint), text);
      await tester.pump();
    }

    testWidgets(
      'come after Health on one screen, then the weight goal, and skipping saves nothing',
      (tester) async {
        final adapter = aboutServer();
        final app = await toAbout(tester, adapter, connect: true);
        expect(app.health.accessRequests, 1);
        for (final hint in ['For example 1990', 'e.g. 5', 'e.g. 10', 'For example 160']) {
          expect(find.widgetWithText(TextField, hint), findsOneWidget, reason: hint);
        }
        await app.tapButton('Skip for now');
        expect(find.text('What is your weight goal?'), findsOneWidget);
        await app.tapButton('Skip');
        expect(find.text('When do you usually wake up?'), findsOneWidget);
        expect(adapter.to('PATCH /api/me'), hasLength(1), reason: 'only the units');
        expect(
          adapter.to('PUT /api/health/daily').where((r) => '${r.data}'.contains('manual')),
          isEmpty,
          reason: 'no weigh-in was typed; only the Health sync writes',
        );
      },
    );

    testWidgets('metric answers save in one PATCH and one weigh-in', (tester) async {
      final adapter = aboutServer();
      final app = await toAbout(tester, adapter, units: 'Kilograms and centimetres');
      await enterField(tester, 'For example 1990', '1990');
      await app.tapText('Female');
      await enterField(tester, 'For example 178', '165');
      await enterField(tester, 'For example 72.5', '60.5');
      await app.tapButton('Continue');
      expect(app.lastBody('PATCH /api/me'), {
        'birthYear': 1990,
        'heightCm': 165.0,
        'sex': 'female',
      });
      final weigh = (app.lastBody('PUT /api/health/daily')['items'] as List).single as Map;
      expect(weigh['metric'], 'weight_kg');
      expect(weigh['value'], 60.5);
      expect(find.text('What is your weight goal?'), findsOneWidget);
    });

    testWidgets('feet, inches and pounds are stored as centimetres and kilograms', (tester) async {
      final adapter = aboutServer();
      final app = await toAbout(tester, adapter);
      await enterField(tester, 'e.g. 5', '5');
      await enterField(tester, 'e.g. 10', '6');
      await enterField(tester, 'For example 160', '150');
      await app.tapButton('Continue');
      expect(app.lastBody('PATCH /api/me'), {'heightCm': 167.6});
      final weigh = (app.lastBody('PUT /api/health/daily')['items'] as List).single as Map;
      expect(weigh['value'], 68.0);
    });

    testWidgets('the weight goal offers paces in pounds', (tester) async {
      final adapter = aboutServer();
      final app = await toAbout(tester, adapter);
      await app.tapButton('Skip for now');
      await app.tapText('Lose');
      expect(find.text('0.5 lb a week'), findsOneWidget);
      expect(find.text('1 lb a week'), findsOneWidget);
      await app.tapText('1 lb a week');
      await app.tapButton('Continue');
      expect(app.lastBody('PATCH /api/me')['goal'], {'kind': 'lose', 'paceKgPerWeek': 0.45});
    });

    testWidgets('Health is asked first so its height and weight are prefilled and kept off the '
        'profile', (tester) async {
      final adapter = aboutServer(targets: 'targets');
      final app = await toAbout(tester, adapter, connect: true);
      expect(find.text('From Apple Health'), findsNWidgets(2));
      final weight = tester.widget<TextField>(
        find.descendant(
          of: find.bySemanticsLabel('Weight in pounds'),
          matching: find.byType(TextField),
        ),
      );
      expect(weight.controller!.text, '181.7');
      final patches = adapter.to('PATCH /api/me').length;
      await app.tapButton('Continue');
      expect(adapter.to('PATCH /api/me').length, patches, reason: 'Health keeps supplying them');
      expect(
        adapter.to('PUT /api/health/daily').where((r) => '${r.data}'.contains('manual')),
        isEmpty,
      );
    });

    testWidgets('a slow first Health sync fills the empty fields when it lands', (tester) async {
      final adapter = aboutServer()
        ..on(
          'GET /api/targets',
          const StubResponse(200, {'inputs': [], 'targets': [], 'sources': {}}),
        );
      final app = _App(tester, adapter);
      app.health.latency = const Duration(seconds: 2);
      await app.joinFirst();
      await app.tapText('Pounds and feet');
      await app.tapButton('Continue');
      await app.tapButton('Connect Apple Health');
      expect(find.text('About you'), findsOneWidget, reason: 'Health no longer holds the screen');
      expect(find.text('From Apple Health'), findsNothing);
      // The sync lands and the server now has Health's height and weight.
      adapter.on('GET /api/targets', StubResponse(200, _targets('targets')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await app.settle();
      expect(find.text('From Apple Health'), findsNWidgets(2));
      expect(find.widgetWithText(TextField, '181.7'), findsOneWidget);
    });

    testWidgets('the back arrow returns from the goal to About you', (tester) async {
      final app = await toAbout(tester, aboutServer());
      await app.tapButton('Skip for now');
      expect(find.text('What is your weight goal?'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('Back'));
      expect(find.text('About you'), findsOneWidget);
    });

    testWidgets('leaving at the weight goal resumes there', (tester) async {
      final adapter = aboutServer();
      final first = await toAbout(tester, adapter);
      await first.tapButton('Skip for now');
      expect(find.text('What is your weight goal?'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onboardingProgress'), contains('"aboutDone":1'));

      await relaunchWith(tester, first, adapter);
      expect(find.text('What is your weight goal?'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('every new screen fits 390 wide at text scale $scale with 44pt buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = _App(tester, aboutServer(targets: 'targets'));
        await app.joinFirst();
        Future<void> check(String screen) async {
          expect(tester.takeException(), isNull, reason: screen);
          for (final b in tester.widgetList<ChunkyButton>(find.byType(ChunkyButton))) {
            expect(
              tester.getSize(find.byWidget(b)).height,
              greaterThanOrEqualTo(44),
              reason: screen,
            );
          }
        }

        await check('units');
        await app.tapButton('Continue');
        await check('health');
        await app.tapButton('Not now');
        await check('about you');
        await app.tapButton('Skip for now');
        await check('weight goal');
        await app.tapButton('Skip');
        await check('schedule');
        await app.tapButton('Use 7:00 AM and 11:00 PM');
        await app.tapText('Eat well');
        await app.tapButton('Continue');
        await check('daily goals');
      });
    }
  });

  group('the schedule step', () {
    Future<_App> toSchedule(WidgetTester tester, StubAdapter adapter) async {
      final app = _App(tester, adapter);
      await app.joinFirst();
      await app.unitsToSchedule();
      expect(find.text('When do you usually wake up?'), findsOneWidget);
      return app;
    }

    testWidgets('follows the weight goal and saves one wake and bed time for every day', (
      tester,
    ) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final app = await toSchedule(tester, adapter);
      expect(app.enabled('Continue'), isTrue, reason: '7:00 AM and 11:00 PM are already chosen');

      await app.tapText('6:00 AM');
      await app.tapText('10:00 PM');
      await app.tapButton('Continue');

      expect(app.lastBody('PATCH /api/me'), {
        'schedule': {
          'workdays': [1, 2, 3, 4, 5],
          'workday': {'wake': '06:00', 'bed': '22:00'},
          'dayOff': {'wake': '06:00', 'bed': '22:00'},
          'firstNotificationOffsetMin': 10,
        },
      });
      expect(find.text('What do you want to work on?'), findsOneWidget);
    });

    testWidgets('the default button sends nothing and moves on', (tester) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final app = await toSchedule(tester, adapter);
      await app.tapButton('Use 7:00 AM and 11:00 PM');
      expect(adapter.to('PATCH /api/me'), hasLength(1), reason: 'only the units, no schedule');
      expect(find.text('What do you want to work on?'), findsOneWidget);
    });

    testWidgets('a failed save says why and stays', (tester) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final app = await toSchedule(tester, adapter);
      adapter.on('PATCH /api/me', const StubResponse(422, {'error': 'wake and bed must differ'}));
      await app.tapButton('Continue');
      expect(find.text('wake and bed must differ'), findsOneWidget);
      expect(find.text('When do you usually wake up?'), findsOneWidget);
    });

    testWidgets('going back from the next step returns to it, with the answer kept', (
      tester,
    ) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final app = await toSchedule(tester, adapter);
      await app.tapText('8:00 AM');
      await app.tapButton('Continue');
      await app.tap(find.bySemanticsLabel('Back'));
      expect(find.text('When do you usually wake up?'), findsOneWidget);
    });

    testWidgets('leaving at the step resumes there, and answering it moves on for good', (
      tester,
    ) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final first = await toSchedule(tester, adapter);

      await tester.pumpWidget(const SizedBox());
      final relaunch = _App(tester, adapter)..storage.values.addAll(first.storage.values);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
            deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
            healthSourceProvider.overrideWithValue(relaunch.health),
            reminderSchedulerProvider.overrideWithValue(relaunch.reminders),
          ],
          child: const NewMeApp(),
        ),
      );
      await relaunch.settle();
      expect(find.text('When do you usually wake up?'), findsOneWidget);
      expect(find.text('Today'), findsNothing);

      await relaunch.tapButton('Use 7:00 AM and 11:00 PM');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('onboardingProgress'), contains('"scheduleAnswered":true'));
      expect(find.text('What do you want to work on?'), findsOneWidget);
    });

    testWidgets('a returning person is not asked, their schedule is already on the server', (
      tester,
    ) async {
      final adapter = _server()
        ..on(
          'POST /api/join',
          const StubResponse(201, {
            'user': {
              'id': 1,
              'name': 'Nick',
              'color': 'amber',
              'timezone': 'America/New_York',
              'isAdmin': true,
            },
            'token': 'repaired-token',
          }),
        );
      final app = _App(tester, adapter);
      await app.launch();
      await app.tapButton('Join with a code');
      await app.enter(_code);
      await app.tapButton('Continue');
      await app.tapText('I have been here before');
      await app.tapText('Nick');
      await app.tapButton('Continue');
      expect(find.text('When do you usually wake up?'), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits 390 wide at text scale $scale with 44pt buttons', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final adapter = _server(info: {..._info, 'initialized': false});
        final app = await toSchedule(tester, adapter);
        expect(tester.takeException(), isNull);
        for (final b in tester.widgetList<ChunkyButton>(find.byType(ChunkyButton))) {
          expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(44));
        }
        await app.tapText('6:00 AM');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('after a forced sign-out the code screen says what happened', (tester) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch(session: () => SessionController.seeded(testSession));
    await app.expectSignedIn();
    adapter.on('GET /api/me', const StubResponse(401, {'error': 'revoked'}));

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    unawaited(container.read(apiClientProvider)!.me().then((_) {}, onError: (_) {}));
    await app.settle();

    expect(find.text('You were signed out. Enter a code to come back.'), findsOneWidget);
    expect(adapter.to('GET /api/server-info').last.uri.host, 'me.invalid');
  });

  testWidgets('a snackbar from the signed-out session does not follow to onboarding', (
    tester,
  ) async {
    final app = _App(tester, _server());
    await app.launch(session: () => SessionController.seeded(testSession));
    final context = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added Meal')));
    await app.settle();
    expect(find.text('Added Meal'), findsOneWidget);

    final container = ProviderScope.containerOf(context);
    unawaited(container.read(sessionProvider.notifier).signOut());
    await app.settle();

    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    expect(find.text('Added Meal'), findsNothing);
  });

  testWidgets('a 426 anywhere in the app blocks it with the update screen', (tester) async {
    final adapter = _server()..on('GET /api/me', const StubResponse(426, {'error': 'old'}));
    final app = _App(tester, adapter);
    await app.launch(session: () => SessionController.seeded(testSession));

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    unawaited(container.read(apiClientProvider)!.me().then((_) {}, onError: (_) {}));
    await app.settle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });
}
