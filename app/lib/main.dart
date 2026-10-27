import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/session.dart';
import 'theme/accent.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[NEWME] FlutterError: ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[NEWME] $error');
      return true;
    };
    runApp(const ProviderScope(child: NewMeApp()));
  }, (error, stack) => debugPrint('[NEWME] uncaught: $error'));
}

class NewMeApp extends ConsumerWidget {
  const NewMeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionProvider);
    final session = state.session;
    final Widget home = !state.restored
        ? const Scaffold(body: SizedBox.shrink())
        : (session != null ? const HomeShell() : const OnboardingScreen());

    return MaterialApp(
      title: 'New Me',
      debugShowCheckedModeBanner: false,
      theme: themeFor(accentById(session?.color)),
      home: home,
    );
  }
}
