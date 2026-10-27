import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/avatar.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import 'code_boxes.dart';
import 'onboarding_controller.dart';
import 'server_sheet.dart';
import 'step_layout.dart';

/// Holding the mascot for three seconds opens the server override, which only test builds need.
class _HiddenServerHold extends ConsumerStatefulWidget {
  const _HiddenServerHold({required this.child});

  final Widget child;

  @override
  ConsumerState<_HiddenServerHold> createState() => _HiddenServerHoldState();
}

class _HiddenServerHoldState extends ConsumerState<_HiddenServerHold> {
  Timer? _hold;

  void _start() {
    _hold?.cancel();
    _hold = Timer(const Duration(seconds: 3), _open);
  }

  void _cancel() => _hold?.cancel();

  Future<void> _open() async {
    HapticFeedback.mediumImpact();
    final controller = ref.read(onboardingProvider.notifier);
    final address = await showServerSheet(context, ref.read(onboardingProvider).serverUrl);
    if (address != null) await controller.connectTo(address);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _start(),
    onPointerUp: (_) => _cancel(),
    onPointerCancel: (_) => _cancel(),
    child: widget.child,
  );
}

class ProbingStep extends StatelessWidget {
  const ProbingStep({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Mascot(size: 120, state: MascotState.thinking));
}

class ServerFailedStep extends ConsumerWidget {
  const ServerFailedStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(onboardingProvider.select((s) => s.failure));
    final update = failure == ProbeFailure.updateRequired;
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Try again',
          onPressed: ref.read(onboardingProvider.notifier).retryProbe,
        ),
      ],
      children: [
        const SizedBox(height: 72),
        const _HiddenServerHold(
          child: Center(child: Mascot(size: 160, state: MascotState.sad)),
        ),
        const SizedBox(height: 28),
        Text(
          update ? 'Time to update' : 'New Me cannot be reached right now',
          textAlign: TextAlign.center,
          style: AppText.title,
        ),
        const SizedBox(height: 8),
        Text(
          update
              ? 'This version is too old. Update it from TestFlight.'
              : failure == ProbeFailure.wrongAddress
              ? ProbeFailure.wrongAddress.message
              : 'Check your connection, then try again.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    );
  }
}

class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialised = ref.watch(onboardingProvider.select((s) => s.info?.initialized ?? false));
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      footer: [
        // Once someone has joined, everyone after them needs a code, so one button is honest.
        if (initialised)
          ChunkyButton(label: 'Join with a code', onPressed: controller.haveCode)
        else
          ChunkyButton(label: 'Get started', onPressed: controller.begin),
      ],
      children: [
        const SizedBox(height: 56),
        const _HiddenServerHold(
          child: Center(child: Mascot(size: 176, state: MascotState.happy)),
        ),
        const SizedBox(height: 24),
        const Text('New Me', textAlign: TextAlign.center, style: AppText.display),
        const SizedBox(height: 8),
        Text(
          'A daily game for two.\nSmall habits, big year.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(fontSize: 18, color: kInkSecondary),
        ),
      ],
    );
  }
}

class CodeStep extends ConsumerStatefulWidget {
  const CodeStep({super.key});

  @override
  ConsumerState<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<CodeStep> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _code.text = ref.read(onboardingProvider).code;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.replaceAll('-', '').length == kInviteCodeLength;

  void _submit() {
    if (_complete) ref.read(onboardingProvider.notifier).submitCode(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    return StepLayout(
      footer: [
        ChunkyButton(label: 'Continue', busy: state.busy, onPressed: _complete ? _submit : null),
      ],
      children: [
        MascotLine(
          line: state.error == null ? 'Got an invite? Type it in.' : 'Hmm, that did not work.',
          state: state.error == null ? MascotState.idle : MascotState.thinking,
        ),
        StepTitle(
          'Enter your invite code',
          subtitle: state.signedOut
              ? 'You were signed out. Enter a code to come back.'
              : 'Ask for one in New Me on the other phone.',
        ),
        CodeBoxes(
          controller: _code,
          hasError: state.error != null,
          shakeTick: state.errorTick,
          onChanged: (_) => setState(() {}),
          onSubmitted: _submit,
        ),
        if (state.error != null) StepError(state.error!),
      ],
    );
  }
}

class ChooseStep extends ConsumerWidget {
  const ChooseStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(onboardingProvider.notifier);
    return StepLayout(
      children: [
        const MascotLine(line: 'The code works!'),
        const StepTitle('Have you used New Me before?'),
        ChoiceCard(
          icon: Icons.waving_hand_rounded,
          title: 'I am new here',
          subtitle: 'Set up your profile',
          onTap: controller.chooseNew,
        ),
        const SizedBox(height: kCardGap),
        ChoiceCard(
          icon: Icons.history_rounded,
          title: 'I have been here before',
          subtitle: 'Pick your profile and jump back in',
          onTap: controller.chooseReturning,
        ),
      ],
    );
  }
}

class WhoStep extends ConsumerWidget {
  const WhoStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final people = state.invite?.users ?? const [];
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Continue',
          busy: state.busy,
          onPressed: state.selectedUserId == null ? null : controller.repairSelected,
        ),
      ],
      children: [
        const MascotLine(line: 'Welcome back!', state: MascotState.happy),
        const StepTitle('Who are you?'),
        for (final (i, user) in people.indexed) ...[
          if (i > 0) const SizedBox(height: kCardGap),
          ChoiceCard(
            title: user.name,
            palette: accentById(user.color),
            selected: state.selectedUserId == user.id,
            showCheck: true,
            leading: Avatar(name: user.name, palette: accentById(user.color), size: 48),
            onTap: () => controller.selectPerson(user.id),
          ),
        ],
        if (state.error != null) StepError(state.error!),
      ],
    );
  }
}
