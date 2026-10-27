import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/confetti.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pop_in.dart';
import 'milestone_copy.dart';
import 'milestones_page.dart';

/// Plays one milestone full screen. Resolves when the person taps through.
Future<void> showMilestoneCelebration(BuildContext context, Milestone milestone) {
  HapticFeedback.heavyImpact();
  final route = MediaQuery.disableAnimationsOf(context)
      ? PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => MilestoneCelebration(milestone: milestone),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          fullscreenDialog: true,
        )
      : PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => MilestoneCelebration(milestone: milestone),
          transitionDuration: kPageDuration,
          reverseTransitionDuration: kMotionDuration,
          fullscreenDialog: true,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        );
  return Navigator.of(context).push(route);
}

/// A full-screen moment for a streak length or a first, with confetti and one button.
class MilestoneCelebration extends StatelessWidget {
  const MilestoneCelebration({super.key, required this.milestone});

  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final m = milestone;
    final palette = milestonePalette(m);
    final number = milestoneNumber(m);
    return Scaffold(
      backgroundColor: kCanvas,
      body: Stack(
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
                          child: Center(
                            child: MergeSemantics(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Mascot(size: 140, state: MascotState.cheer),
                                  const SizedBox(height: 20),
                                  PopIn(
                                    child: SizedBox.square(
                                      dimension: 132,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: palette.tint,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: palette.fill, width: 6),
                                        ),
                                        child: Center(
                                          child: number == null
                                              ? Icon(milestoneIcon(m), size: 64, color: palette.lip)
                                              : MediaQuery.withNoTextScaling(
                                                  child: Text(
                                                    number,
                                                    style: AppText.tabular(
                                                      AppText.display.copyWith(
                                                        fontSize: number.length > 2 ? 44 : 56,
                                                        color: palette.lip,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(milestoneOwner(m), style: AppText.caption),
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      m.title,
                                      textAlign: TextAlign.center,
                                      style: AppText.display,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    milestoneBody(m),
                                    textAlign: TextAlign.center,
                                    style: AppText.headline.copyWith(
                                      color: kInkSecondary,
                                      fontWeight: FontWeight.w700,
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
                  ChunkyButton(label: 'Keep going', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
