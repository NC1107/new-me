import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = Session(
  baseUrl: 'https://me.invalid',
  token: 'tok',
  userId: 2,
  userName: 'Sam',
  color: 'violet',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secure = <String, String>{};

  setUp(() {
    secure.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async {
        final args = call.arguments as Map;
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secure[key];
          case 'write':
            secure[key!] = args['value'] as String;
          case 'delete':
            secure.remove(key);
        }
        return null;
      },
    );
  });

  test('a seeded controller is restored with its session and builds a client', () {
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWith(() => SessionController.seeded(_session))],
    );
    addTearDown(container.dispose);
    expect(container.read(sessionProvider).restored, isTrue);
    expect(container.read(sessionProvider).session!.userName, 'Sam');
    expect(container.read(apiClientProvider), isNotNull);
  });

  test('empty storage restores to signed out', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(sessionProvider).restored, isFalse);
    await container.read(sessionProvider.notifier).restoreDone;
    expect(container.read(sessionProvider).restored, isTrue);
    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(apiClientProvider), isNull);
  });

  test('sign in persists the token securely and the rest in prefs, then restores', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(sessionProvider.notifier).signIn(_session);
    expect(secure['token'], 'tok');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session'), isNot(contains('tok')));

    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(second.read(sessionProvider).restored, isFalse);
    await second.read(sessionProvider.notifier).restoreDone;
    final restored = second.read(sessionProvider).session!;
    expect((restored.token, restored.userId, restored.color), ('tok', 2, 'violet'));
  });

  test('sign out clears both stores', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier);
    await controller.signIn(_session);
    await controller.signOut();
    expect(container.read(sessionProvider).session, isNull);
    expect(secure, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('session'), isNull);
  });
}
