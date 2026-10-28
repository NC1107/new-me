import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A slim 8 tall bar for the macro rows; the thick bar is reserved for the main goals.
const kMiniBarHeight = 8.0;

class MiniBar extends StatelessWidget {
  const MiniBar({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: kMiniBarHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value.isNaN ? 0 : value.clamp(0.0, 1.0)),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: kSunken,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
