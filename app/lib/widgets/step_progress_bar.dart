import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'thick_progress_bar.dart';

/// The top of an onboarding screen: a back arrow and the progress bar.
/// Without [onBack] the arrow's space is kept so the bar does not shift between screens.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({super.key, required this.progress, this.onBack});

  /// 0 to 1 across the whole flow.
  final double progress;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: onBack == null
              ? null
              : Semantics(
                  button: true,
                  label: 'Back',
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onBack!();
                    },
                    radius: 24,
                    child: const Center(
                      child: Icon(Icons.arrow_back_rounded, size: 28, color: kInkSecondary),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: ThickProgressBar(value: progress, semanticLabel: 'Progress'),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}
