import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A shared progress bar that blends two people's colours, because the number it shows belongs
/// to both of them. Same 16 tall pill as the quest bars.
class TogetherBar extends StatelessWidget {
  const TogetherBar({
    super.key,
    required this.value,
    required this.from,
    required this.to,
    this.semanticLabel,
  });

  static const height = 16.0;

  /// 0 to 1; clamped.
  final double value;
  final Color from;
  final Color to;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final instant = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticLabel,
      value: semanticLabel == null ? null : '${(target * 100).round()}%',
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kSunken,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: target),
                duration: instant ? Duration.zero : const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) {
                  if (v <= 0) return const SizedBox.shrink();
                  // Never narrower than the bar is tall, so a sliver still reads as a pill.
                  final w = (box.maxWidth * v).clamp(height, box.maxWidth);
                  return Container(
                    width: w,
                    height: height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [from, to]),
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.fromLTRB(5.6, 3.2, 5.6, 0),
                    child: w > height
                        ? Container(
                            height: height * 0.26,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.32),
                              borderRadius: BorderRadius.circular(height * 0.13),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
