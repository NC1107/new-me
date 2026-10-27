import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/state/session.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server({bool admin = false}) => fullServer()
  ..on('GET /api/me', StubResponse(200, meJson(admin: admin)))
  ..on('PATCH /api/me', StubResponse(200, meJson(admin: admin)));

TestApp _app(WidgetTester tester, StubAdapter adapter) =>
    TestApp(tester, adapter, surfaceHeight: 4200);

void main() {
  setUp(FakeStorage().install);

  testWidgets('shows the profile, targets, quests with the tomorrow note, health and about', (
    tester,
  ) async {
    final app = _app(tester, _server());
    await app.pump(const MeScreen());

    expect(find.text('Sam'), findsWidgets);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('America/New_York'), findsOneWidget);
    expect(fieldWith('2200'), findsOneWidget);
    expect(fieldWith('150'), findsOneWidget);

    expect(find.text('Takes effect tomorrow'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Yoga'), findsOneWidget);
    expect(fieldWith('8000'), findsOneWidget);
    expect(fieldWith('30'), findsOneWidget);
    expect(fieldWith('15'), findsOneWidget);

    expect(find.text('Connect Health'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('me.invalid'), findsOneWidget);
    expect(find.text('Create pairing code'), findsNothing);
    expect(find.text('Leave this server'), findsOneWidget);
  });

  testWidgets('quest switches and target fields are named for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    final app = _app(tester, _server());
    await app.pump(const MeScreen());

    expect(find.bySemanticsLabel('Pushups'), findsWidgets);
    expect(tester.getSemantics(fieldWith('30')).label, contains('Pushups Target (reps)'));
    expect(tester.getSemantics(fieldWith('2200')).label, contains('Calories (kcal)'));
    handle.dispose();
  });

  testWidgets('a quest edit sends only what changed and is disabled until then', (tester) async {
    final adapter = _server();
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widgetList<FilledButton>(save).every((b) => b.onPressed == null), isTrue);

    await app.enter(fieldWith('30'), '40');
    await app.tap(find.byType(Switch).last);
    await app.tap(find.widgetWithText(FilledButton, 'Save').at(2));

    expect(app.body('PATCH /api/me'), {
      'questTemplates': [
        {'key': 'pushups', 'target': 40},
        {'key': 'yoga', 'enabled': true},
      ],
    });
  });

  testWidgets('targets save only the edited fields', (tester) async {
    final adapter = _server();
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.enter(fieldWith('2200'), '2400');
    await app.tap(find.widgetWithText(FilledButton, 'Save').at(1));
    expect(app.body('PATCH /api/me'), {
      'targets': {'kcal': 2400},
    });
  });

  testWidgets('a color change saves and recolors the app', (tester) async {
    final adapter = _server()..on('PATCH /api/me', StubResponse(200, meJson(color: 'amber')));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.tap(find.text('Honey'));
    await app.tap(find.widgetWithText(FilledButton, 'Save').first);

    expect(app.body('PATCH /api/me'), {'color': 'amber'});
    expect(app.container.read(sessionProvider).session!.color, 'amber');
  });

  testWidgets('colors the other person has are disabled', (tester) async {
    final adapter = _server()
      ..on(
        'GET /api/board',
        StubResponse(200, board([boardUser(2, 'Sam', 'violet'), boardUser(1, 'Ana', 'sky')])),
      );
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    await app.tap(find.text('Sky'));
    expect(
      tester.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Save')).first.onPressed,
      isNull,
    );
  });

  testWidgets('a taken name shows the server message and offers a retry', (tester) async {
    final adapter = _server()
      ..on('PATCH /api/me', const StubResponse(409, {'error': 'That name is taken'}));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.enter(fieldWith('Sam'), 'Ana');
    await app.tap(find.widgetWithText(FilledButton, 'Save').first);
    expect(find.text('That name is taken'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('the time zone sheet lists zones and shows the server verdict on free text', (
    tester,
  ) async {
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
    await app.enter(find.widgetWithText(TextField, '').last, 'Mars/Base');
    await app.tap(find.text('Use this zone'));
    expect(find.text('The server does not know "Mars/Base".'), findsOneWidget);

    adapter.on('PATCH /api/me', StubResponse(200, {...meJson(), 'timezone': 'Europe/London'}));
    await app.tap(find.text('Europe/London'));
    expect(app.body('PATCH /api/me'), {'timezone': 'Europe/London'});
    expect(find.text('Use this zone'), findsNothing);
  });

  testWidgets('an admin can create a pairing code, see it large and copy it', (tester) async {
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

    await app.tap(find.text('Create pairing code'));
    expect(find.text('K7Q2-M9XD'), findsOneWidget);
    expect(find.textContaining('Expires at'), findsOneWidget);

    await app.tap(find.byIcon(Icons.copy_rounded));
    expect(copied, ['K7Q2-M9XD']);
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('connecting Health from Me asks for access once', (tester) async {
    final adapter = _server()
      ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.tap(find.widgetWithText(FilledButton, 'Connect Health'));
    expect(app.health.accessRequests, 1);
    expect(find.widgetWithText(FilledButton, 'Connect Health'), findsNothing);
    expect(find.text('Last sync just now'), findsOneWidget);
  });

  testWidgets('leaving asks first, revokes the device and signs out', (tester) async {
    final adapter = _server()..on('DELETE /api/devices/me', const StubResponse(204));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.tap(find.text('Leave this server'));
    expect(find.text('Leave this server?'), findsOneWidget);
    await app.tap(find.text('Cancel'));
    expect(app.container.read(sessionProvider).session, isNotNull);

    await app.tap(find.text('Leave this server'));
    await app.tap(find.text('Leave'));
    expect(app.container.read(sessionProvider).session, isNull);
    expect(adapter.to('DELETE /api/devices/me'), hasLength(1));
  });

  testWidgets('an admin is warned that only the server can bring them back', (tester) async {
    final app = _app(tester, _server(admin: true));
    await app.pump(const MeScreen());

    await app.tap(find.text('Leave this server'));
    expect(find.textContaining('You are the admin'), findsOneWidget);
  });

  testWidgets('offline, the cached profile is shown and every edit is disabled', (tester) async {
    final adapter = _server();
    final app = _app(tester, adapter);
    await app.pump(const MeScreen(), key: UniqueKey());

    adapter.on('GET /api/me', const StubResponse.unreachable());
    await app.pump(const MeScreen(), key: UniqueKey());

    expect(find.textContaining('Offline - updated'), findsOneWidget);
    expect(fieldWith('30'), findsOneWidget);
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.onChanged == null),
      isTrue,
    );
    await app.tap(find.text('Time zone'));
    expect(find.text('Use this zone'), findsNothing);
    final guard = find.ancestor(of: fieldWith('30'), matching: find.byType(IgnorePointer));
    expect(tester.widget<IgnorePointer>(guard.first).ignoring, isTrue);
  });

  testWidgets('saving the profile does not reload Me', (tester) async {
    final adapter = _server()..on('PATCH /api/me', StubResponse(200, meJson(color: 'amber')));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());
    final loads = adapter.to('GET /api/me').length;

    await app.tap(find.text('Honey'));
    await app.tap(find.widgetWithText(FilledButton, 'Save').first);

    expect(adapter.to('PATCH /api/me'), hasLength(1));
    expect(adapter.to('GET /api/me'), hasLength(loads));
  });

  testWidgets('saving one section keeps what is typed in the others', (tester) async {
    final adapter = _server()..on('PATCH /api/me', StubResponse(200, meJson(color: 'amber')));
    final app = _app(tester, adapter);
    await app.pump(const MeScreen());

    await app.enter(fieldWith('2200'), '2400');
    await app.enter(fieldWith('30'), '45');
    await app.tap(find.text('Honey'));
    await app.tap(find.widgetWithText(FilledButton, 'Save').first);

    expect(fieldWith('2400'), findsOneWidget);
    expect(fieldWith('45'), findsOneWidget);
  });
}
