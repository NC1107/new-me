import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A pulsing placeholder block, the app's only loading idiom (no shimmer).
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({super.key, this.width, this.height = 16, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: kBgSurfaceHover.withValues(alpha: 0.35 + 0.35 * _pulse.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
