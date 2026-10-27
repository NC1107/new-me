import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/update_required_screen.dart';
import 'state/reminders.dart';
import 'state/session.dart';
import 'state/update_gate.dart';
import 'theme/accent.dart';
import 'theme/tokens.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kReleaseMode && kAppKey.isEmpty) {
      throw StateError('Release builds need --dart-define=NEWME_APP_KEY');
    }
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[NEWME] FlutterError: ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[NEWME] $error');
      return true;
    };
    // A failed read is shown with Try again instead of silently retried in the background.
    runApp(ProviderScope(retry: (retryCount, error) => null, child: const NewMeApp()));
  }, (error, stack) => debugPrint('[NEWME] uncaught: $error'));
}

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class NewMeApp extends ConsumerWidget {
  const NewMeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider);
    ref.listen(sessionProvider.select((s) => s.session?.userId), (_, userId) {
      if (userId == null) _messengerKey.currentState?.clearSnackBars();
    });
    final session = state.session;
    final updateRequired = ref.watch(updateGateProvider);
    final onboarding = ref.watch(
      onboardingProvider.select((s) => (loaded: s.loaded, pending: s.pending)),
    );

    final Widget home = updateRequired
        ? const UpdateRequiredScreen()
        : !state.restored || !onboarding.loaded
        ? const Scaffold(body: SizedBox.shrink())
        : (session != null && !onboarding.pending ? const HomeShell() : const OnboardingScreen());

    return MaterialApp(
      title: 'New Me',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: rootNavigatorKey,
      theme: themeFor(accentById(session?.color)),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: ColoredBox(
          color: kCanvas,
          // Only the web test build is ever wider than a phone.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: child,
            ),
          ),
        ),
      ),
      home: home,
    );
  }
}
