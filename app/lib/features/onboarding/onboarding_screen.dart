import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../widgets/step_progress_bar.dart';
import 'onboarding_controller.dart';
import 'steps_entry.dart';
import 'steps_finish.dart';
import 'steps_plan.dart';
import 'steps_profile.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(onboardingProvider.notifier).start();
    });
  }

  static bool _showsBar(OnboardingStep step) => switch (step) {
    OnboardingStep.probing || OnboardingStep.serverFailed || OnboardingStep.welcome => false,
    _ => true,
  };

  Widget _page(OnboardingState state) => switch (state.step) {
    OnboardingStep.probing => const ProbingStep(),
    OnboardingStep.serverFailed => const ServerFailedStep(),
    OnboardingStep.welcome => const WelcomeStep(),
    OnboardingStep.code => const CodeStep(),
    OnboardingStep.choose => const ChooseStep(),
    OnboardingStep.who => const WhoStep(),
    OnboardingStep.name => const NameStep(),
    OnboardingStep.color => const ColorStep(),
    OnboardingStep.focus => const FocusStep(),
    OnboardingStep.goals => const GoalStep(),
    OnboardingStep.food => const FoodStep(),
    OnboardingStep.health => const HealthStep(),
    OnboardingStep.done => const DoneStep(),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final key = ValueKey((state.step, state.goalIndex));

    return Theme(
      data: themeFor(accentById(state.color)),
      child: Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              if (_showsBar(state.step))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StepProgressBar(
                    progress: state.progress,
                    onBack: state.canGoBack ? controller.back : null,
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : kPageDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) =>
                      Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == key;
                    final shift = (state.forward ? 1.0 : -1.0) * 0.12;
                    final offset = Tween<Offset>(
                      begin: Offset(incoming ? shift : -shift, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: KeyedSubtree(key: key, child: _page(state)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
