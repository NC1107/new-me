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

/// Loading shape of Today: the ring and three quest cards.
class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
    children: [
      const Center(child: SkeletonBlock(width: 216, height: 216, radius: 108)),
      const SizedBox(height: 18),
      const Center(child: SkeletonBlock(width: 200, height: 14)),
      const SizedBox(height: 20),
      for (var i = 0; i < 3; i++) ...[const _CardSkeleton(), const SizedBox(height: 10)],
    ],
  );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 92,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kBgSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBlock(width: 110, height: 16),
        Spacer(),
        SkeletonBlock(height: 6, radius: 3),
        SizedBox(height: 10),
        SkeletonBlock(width: 80, height: 12),
      ],
    ),
  );
}

/// Loading shape of the Board: one tall card per column.
class BoardSkeleton extends StatelessWidget {
  const BoardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i == 1) const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 360,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kBgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(width: 70, height: 16),
                  SizedBox(height: 24),
                  SkeletonBlock(width: 90, height: 40),
                  SizedBox(height: 10),
                  SkeletonBlock(width: 40, height: 14),
                  SizedBox(height: 32),
                  SkeletonBlock(height: 14),
                  SizedBox(height: 12),
                  SkeletonBlock(height: 14),
                  SizedBox(height: 32),
                  SkeletonBlock(height: 10),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Loading shape of Me: a few stacked rows.
class MeSkeleton extends StatelessWidget {
  const MeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
    children: [
      const Row(
        children: [
          SkeletonBlock(width: 56, height: 56, radius: 28),
          SizedBox(width: 14),
          SkeletonBlock(width: 140, height: 20),
        ],
      ),
      const SizedBox(height: 28),
      for (var i = 0; i < 4; i++) ...[
        const SkeletonBlock(height: 52, radius: 14),
        const SizedBox(height: 10),
      ],
    ],
  );
}
