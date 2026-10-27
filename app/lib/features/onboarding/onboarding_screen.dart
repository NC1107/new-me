import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/accent_picker.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_widgets.dart';
import 'onboarding_controller.dart';

const _kMaxName = 40;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _server = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _server.text = _display(ref.read(onboardingProvider).serverUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(onboardingProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  String _display(String url) => url.replaceFirst('https://', '');

  @override
  Widget build(BuildContext context) {
    ref.listen(onboardingProvider.select((s) => s.serverUrl), (_, url) {
      _server.text = _display(url);
    });
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);

    return Theme(
      data: themeFor(accentById(state.color)),
      child: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'New Me',
                        style: TextStyle(
                          color: kFgPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: KeyedSubtree(
                          key: ValueKey(state.step),
                          child: _step(state, controller),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(OnboardingState state, OnboardingController controller) => switch (state.step) {
    OnboardingStep.probing => _Probing(url: _display(state.serverUrl)),
    OnboardingStep.serverFailed => _ServerFailed(
      message: state.failure?.message ?? '',
      controller: _server,
      onConnect: () => controller.connectTo(_server.text),
    ),
    OnboardingStep.firstJoin => _ProfileStep(
      title: 'What should we call you?',
      subtitle: 'You are the first one here.',
      action: 'Create profile',
      nameController: _name,
      state: state,
      takenColors: const {},
      onColor: controller.setColor,
      onSubmit: () => controller.createProfile(_name.text),
      footer: _ServerLink(state: state, controller: _server, onConnect: controller.connectTo),
      onChangeServer: controller.changeServer,
    ),
    OnboardingStep.code => _CodeStep(
      state: state,
      codeController: _code,
      serverController: _server,
      onSubmit: () => controller.submitCode(_code.text),
      onChangeServer: controller.changeServer,
      onConnect: () => controller.connectTo(_server.text),
    ),
    OnboardingStep.choose => _ChooseStep(
      state: state,
      onNew: controller.chooseNew,
      onUser: controller.repair,
      onBack: controller.back,
    ),
    OnboardingStep.profile => _ProfileStep(
      title: 'What should we call you?',
      subtitle: 'Pick a name and a color for the board.',
      action: 'Join',
      nameController: _name,
      state: state,
      takenColors: state.takenColors,
      onColor: controller.setColor,
      onSubmit: () => controller.createProfile(_name.text),
      onBack: controller.back,
    ),
    OnboardingStep.health => _HealthStep(
      busy: state.busy,
      onConnect: controller.connectHealth,
      onSkip: controller.finish,
    ),
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: kFgSecondary, fontSize: 14, height: 1.4)),
      const SizedBox(height: 24),
    ],
  );
}

class _Probing extends StatelessWidget {
  const _Probing({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: context.accent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          'Connecting to $url',
          style: const TextStyle(color: kFgSecondary, fontSize: 14),
        ),
      ),
    ],
  );
}

class _ServerField extends StatelessWidget {
  const _ServerField({required this.controller, required this.onConnect});

  final TextEditingController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const FieldLabel('Server'),
      AppTextField(
        controller: controller,
        hint: 'new-me.example.com',
        keyboardType: TextInputType.url,
      ),
      const SizedBox(height: 14),
      PrimaryButton(label: 'Connect', enabled: true, onTap: onConnect),
    ],
  );
}

class _ServerFailed extends StatelessWidget {
  const _ServerFailed({required this.message, required this.controller, required this.onConnect});

  final String message;
  final TextEditingController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: kDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: kFgPrimary, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _ServerField(controller: controller, onConnect: onConnect),
    ],
  );
}

/// The quiet link that reveals the server field; the field itself replaces it once tapped.
class _ServerLink extends StatelessWidget {
  const _ServerLink({required this.state, required this.controller, required this.onConnect});

  final OnboardingState state;
  final TextEditingController controller;
  final ValueChanged<String> onConnect;

  @override
  Widget build(BuildContext context) {
    if (!state.showServerField) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: _ServerField(controller: controller, onConnect: () => onConnect(controller.text)),
    );
  }
}

class _ChangeServerButton extends StatelessWidget {
  const _ChangeServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: kFgSecondary, padding: EdgeInsets.zero),
      child: const Text('Change server', style: TextStyle(fontSize: 13)),
    ),
  );
}

class _CodeStep extends StatefulWidget {
  const _CodeStep({
    required this.state,
    required this.codeController,
    required this.serverController,
    required this.onSubmit,
    required this.onChangeServer,
    required this.onConnect,
  });

  final OnboardingState state;
  final TextEditingController codeController;
  final TextEditingController serverController;
  final VoidCallback onSubmit;
  final VoidCallback onChangeServer;
  final VoidCallback onConnect;

  @override
  State<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<_CodeStep> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final ready = widget.codeController.text.trim().isNotEmpty && !state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Enter your code',
          state.signedOut
              ? 'You were signed out. Enter a code to come back.'
              : 'Ask for a pairing code in New Me on the other phone.',
        ),
        const FieldLabel('Pairing code'),
        AppTextField(
          controller: widget.codeController,
          hint: 'Code',
          errorText: state.error,
          onChanged: (_) => setState(() {}),
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Continue', enabled: ready, busy: state.busy, onTap: widget.onSubmit),
        const SizedBox(height: 12),
        if (state.showServerField)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _ServerField(controller: widget.serverController, onConnect: widget.onConnect),
          )
        else
          _ChangeServerButton(onTap: widget.onChangeServer),
      ],
    );
  }
}

class _ChooseStep extends StatelessWidget {
  const _ChooseStep({
    required this.state,
    required this.onNew,
    required this.onUser,
    required this.onBack,
  });

  final OnboardingState state;
  final VoidCallback onNew;
  final ValueChanged<UserSummary> onUser;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final users = state.invite?.users ?? const <UserSummary>[];
    final canJoin = state.info?.joinOpen ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Who are you?',
          canJoin ? 'Pick yourself if you are coming back, or join as new.' : 'Pick yourself.',
        ),
        if (state.error != null) ...[
          Text(state.error!, style: const TextStyle(color: kDanger, fontSize: 13)),
          const SizedBox(height: 12),
        ],
        if (users.isNotEmpty) ...[
          const FieldLabel('Coming back'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final u in users)
                _UserChip(user: u, enabled: !state.busy, onTap: () => onUser(u)),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (canJoin) PrimaryButton(label: "I'm new", enabled: !state.busy, onTap: onNew),
        TextButton(
          onPressed: onBack,
          style: TextButton.styleFrom(foregroundColor: kFgSecondary),
          child: const Text('Use a different code'),
        ),
      ],
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({required this.user, required this.enabled, required this.onTap});

  final UserSummary user;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentById(user.color);
    final initial = user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase();
    return Material(
      color: kBgSurface,
      shape: const StadiumBorder(side: BorderSide(color: kBorder)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accent.base,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: accent.onAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                user.name,
                style: const TextStyle(
                  color: kFgPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStep extends StatefulWidget {
  const _ProfileStep({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.nameController,
    required this.state,
    required this.takenColors,
    required this.onColor,
    required this.onSubmit,
    this.onBack,
    this.footer,
    this.onChangeServer,
  });

  final String title;
  final String subtitle;
  final String action;
  final TextEditingController nameController;
  final OnboardingState state;
  final Set<String> takenColors;
  final ValueChanged<String> onColor;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;
  final Widget? footer;
  final VoidCallback? onChangeServer;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final name = widget.nameController.text.trim();
    final ready = name.isNotEmpty && name.length <= _kMaxName && !state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(widget.title, widget.subtitle),
        const FieldLabel('Name'),
        AppTextField(
          controller: widget.nameController,
          hint: 'Your name',
          errorText: state.error,
          onChanged: (_) => setState(() {}),
          inputFormatters: [LengthLimitingTextInputFormatter(_kMaxName)],
        ),
        const SizedBox(height: 24),
        const FieldLabel('Color'),
        AccentPicker(selected: state.color, taken: widget.takenColors, onChanged: widget.onColor),
        const SizedBox(height: 28),
        PrimaryButton(
          label: widget.action,
          enabled: ready,
          busy: state.busy,
          onTap: widget.onSubmit,
        ),
        if (widget.onBack != null)
          TextButton(
            onPressed: widget.onBack,
            style: TextButton.styleFrom(foregroundColor: kFgSecondary),
            child: const Text('Back'),
          ),
        if (widget.onChangeServer != null && !state.showServerField)
          _ChangeServerButton(onTap: widget.onChangeServer!),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }
}

class _HealthStep extends StatelessWidget {
  const _HealthStep({required this.busy, required this.onConnect, required this.onSkip});

  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Heading(
        'Connect Health',
        'New Me reads your steps and active energy from Apple Health to score your day. '
            'New Me never writes to Health.',
      ),
      PrimaryButton(label: 'Connect Health', enabled: !busy, busy: busy, onTap: onConnect),
      TextButton(
        onPressed: busy ? null : onSkip,
        style: TextButton.styleFrom(foregroundColor: kFgSecondary),
        child: const Text('Skip for now'),
      ),
    ],
  );
}
