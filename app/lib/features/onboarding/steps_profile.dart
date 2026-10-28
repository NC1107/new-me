import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable.dart';
import 'onboarding_controller.dart';
import 'step_layout.dart';

class NameStep extends ConsumerStatefulWidget {
  const NameStep({super.key});

  @override
  ConsumerState<NameStep> createState() => _NameStepState();
}

class _NameStepState extends ConsumerState<NameStep> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(onboardingProvider).name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() => ref.read(onboardingProvider.notifier).continueFromName();

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(onboardingProvider.notifier);
    final ready = ref.watch(
      onboardingProvider.select((s) {
        final n = s.name.trim();
        return n.isNotEmpty && n.length <= kMaxNameLength;
      }),
    );
    return StepLayout(
      footer: [ChunkyButton(label: 'Continue', onPressed: ready ? _continue : null)],
      children: [
        const MascotLine(line: 'Nice to meet you!', state: MascotState.happy),
        const StepTitle('What should we call you?'),
        AppTextField(
          controller: _name,
          hint: 'Your name',
          semanticLabel: 'Your name',
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
          onChanged: controller.setName,
          onSubmitted: (_) => ready ? _continue() : null,
          autofocus: true,
        ),
      ],
    );
  }
}

class ColorStep extends ConsumerWidget {
  const ColorStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final taken = state.takenColors;
    final chosen = accentById(state.color);
    return StepLayout(
      footer: [
        ChunkyButton(
          label: 'Continue',
          busy: state.busy,
          onPressed: taken.contains(state.color) ? null : controller.createProfile,
        ),
      ],
      children: [
        const SizedBox(height: 4),
        Center(
          child: Mascot(size: 128, state: MascotState.happy, palette: chosen),
        ),
        const StepTitle('Pick your color', subtitle: 'This is how you show up on the scoreboard.'),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 12.0;
            final cell = (box.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in kAccentPresets)
                  _Swatch(
                    palette: p,
                    width: cell,
                    selected: p.id == state.color,
                    taken: taken.contains(p.id),
                    onTap: () => controller.setColor(p.id),
                  ),
              ],
            );
          },
        ),
        if (state.error != null) StepError(state.error!),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.width,
    required this.selected,
    required this.taken,
    required this.onTap,
  });

  final AccentPalette palette;
  final double width;
  final bool selected;
  final bool taken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: !taken,
      selected: selected,
      label: taken ? '${palette.name}, taken' : palette.name,
      excludeSemantics: true,
      onTap: taken ? null : onTap,
      child: Pressable(
        onTap: taken ? null : onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: reduce ? Duration.zero : kMotionDuration,
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: taken ? kSunken : palette.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? kInk : Colors.transparent, width: 3),
                  boxShadow: taken
                      ? null
                      : [BoxShadow(color: palette.lip, offset: const Offset(0, 4))],
                ),
                child: taken
                    ? const Icon(Icons.block_rounded, size: 28, color: kInkMuted)
                    : selected
                    ? Icon(Icons.check_rounded, size: 34, color: palette.onFill)
                    : null,
              ),
              const SizedBox(height: 10),
              Text(
                palette.name,
                style: AppText.label.copyWith(
                  color: taken ? kInkMuted : kInk,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              Text(taken ? 'Taken' : '', style: AppText.caption.copyWith(height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }
}
