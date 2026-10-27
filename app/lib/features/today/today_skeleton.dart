import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/skeletons.dart';

/// Loading shape of Today: the greeting, the day card and a few quest cards.
class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
    children: [
      const Row(
        children: [
          SkeletonBlock(width: 40, height: 40, radius: 20),
          Spacer(),
          SkeletonBlock(width: 120, height: 24, radius: 12),
          Spacer(),
          SkeletonBlock(width: 40, height: 40, radius: 20),
        ],
      ),
      const SizedBox(height: 20),
      const SkeletonBlock(width: 200, height: 26),
      const SizedBox(height: 14),
      const SkeletonBlock(height: 84, radius: kRadiusCard),
      const SizedBox(height: kCardGap),
      const _CardSkeleton(height: 132),
      for (var i = 0; i < 3; i++) ...[const SizedBox(height: kCardGap), const _CardSkeleton()],
    ],
  );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorder, width: kBorderWidth),
    ),
    child: const Row(
      children: [
        SkeletonBlock(width: 48, height: 48, radius: 24),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBlock(width: 140, height: 16),
              SizedBox(height: 10),
              SkeletonBlock(height: 16, radius: 8),
            ],
          ),
        ),
      ],
    ),
  );
}
