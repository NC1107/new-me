import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/confetti.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pop_in.dart';

Future<void> showDayCountedSheet(BuildContext context) {
  HapticFeedback.heavyImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSurface,
    builder: (_) => const DayCountedSheet(),
  );
}

/// Shown once a day, the first time the day counts: the mascot cheers, the streak counts up and
/// confetti falls.
class DayCountedSheet extends ConsumerWidget {
  const DayCountedSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(todayProvider.select((t) => t.value?.data.streak.current ?? 1));
    final now = streak < 1 ? 1 : streak;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final person = context.accentPalette;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Mascot(size: 160, state: MascotState.cheer),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: const Text('Day counted!', textAlign: TextAlign.center, style: AppText.display),
        ),
        const SizedBox(height: 20),
        MergeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PopIn(
                child: Icon(Icons.local_fire_department_rounded, size: 64, color: kFlame),
              ),
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: (now - 1).toDouble(), end: now.toDouble()),
                duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}',
                  style: AppText.tabular(
                    AppText.display.copyWith(fontSize: 72, color: person.lip, height: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          now == 1 ? 'day streak' : 'days in a row',
          style: AppText.headline.copyWith(color: kInkSecondary),
        ),
      ],
    );

    return SizedBox.expand(
      child: Stack(
        children: [
          const Positioned.fill(
            child: Confetti(origin: Alignment(0, -0.35), particles: 90, spread: 1.1),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 20),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Center(child: content),
                        ),
                      ),
                    ),
                  ),
                  ChunkyButton(label: 'Continue', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
