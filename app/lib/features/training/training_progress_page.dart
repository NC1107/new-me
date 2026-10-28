import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';

/// Width of each of the three earlier-week columns, shared by the header and the rows.
const _kWeekColumn = 44.0;

/// Where a week's sets sit against the evidence range.
enum VolumeBand { none, under, inRange, over }

VolumeBand volumeBand(int sets, TrainingProgress p) {
  if (sets == 0) return VolumeBand.none;
  if (sets < p.rangeMin) return VolumeBand.under;
  if (p.rangeMax > 0 && sets > p.rangeMax) return VolumeBand.over;
  return VolumeBand.inRange;
}

/// Hard sets per muscle this week against the evidence range, with the three weeks before.
class TrainingProgressPage extends ConsumerWidget {
  const TrainingProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(trainingProgressProvider);
    return PageScaffold(
      title: 'Weekly sets',
      subtitle: 'Hard sets per muscle, counted by primary muscle',
      children: [
        switch (value) {
          AsyncValue(:final value?) => _Body(progress: value),
          AsyncValue(:final error?) => ErrorBlock(
            title: 'Could not load your weekly sets',
            error: error,
            onRetry: () async => ref.invalidate(trainingProgressProvider),
          ),
          _ => const SkeletonBlock(height: 240, radius: kRadiusCard),
        },
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.progress});

  final TrainingProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final scale = [
      p.rangeMax,
      for (final m in p.muscles) m.thisWeek,
    ].reduce((a, b) => a > b ? a : b);
    final hasSets = p.muscles.any((m) => m.weeks.any((w) => w > 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aim for ${p.rangeMin} to ${p.rangeMax} hard sets a week per muscle, the shaded band '
          'on each bar.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 16),
        if (!hasSets) ...[
          Text(
            'No hard sets in the last 4 weeks. Log a set and each muscle fills in here.',
            style: AppText.label.copyWith(color: kInk, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    const Spacer(),
                    for (final weeksAgo in [3, 2, 1])
                      SizedBox(
                        width: _kWeekColumn,
                        child: Text(
                          '$weeksAgo wk',
                          textAlign: TextAlign.right,
                          style: AppText.caption.copyWith(color: kInkMuted),
                        ),
                      ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 64,
                      child: Text(
                        'This week',
                        textAlign: TextAlign.right,
                        style: AppText.caption.copyWith(color: kInkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              for (final m in p.muscles) ...[
                const SizedBox(height: 12),
                _MuscleRow(volume: m, progress: p, scale: scale <= 0 ? 1 : scale),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'The range is ${p.rangeLabel}. Source: ${p.source}.',
          style: AppText.caption.copyWith(color: kInkMuted),
        ),
      ],
    );
  }
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow({required this.volume, required this.progress, required this.scale});

  final MuscleVolume volume;
  final TrainingProgress progress;
  final int scale;

  @override
  Widget build(BuildContext context) {
    final sets = volume.thisWeek;
    final band = volumeBand(sets, progress);
    final earlier = volume.weeks.length > 1
        ? volume.weeks.sublist(0, volume.weeks.length - 1)
        : const <int>[];
    final status = switch (band) {
      VolumeBand.none => 'none yet',
      VolumeBand.under => 'under the range',
      VolumeBand.inRange => 'in range',
      VolumeBand.over => 'over the range',
    };
    return Semantics(
      label:
          '${muscleLabel(volume.muscle)}, $sets ${sets == 1 ? 'set' : 'sets'} this week, $status. '
          'The 3 weeks before: ${earlier.join(', ')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(muscleLabel(volume.muscle), style: AppText.label.copyWith(color: kInk)),
              ),
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: _kWeekColumn,
                  child: Text(
                    i >= 3 - earlier.length ? '${earlier[i - (3 - earlier.length)]}' : '',
                    textAlign: TextAlign.right,
                    style: AppText.tabular(AppText.caption.copyWith(color: kInkMuted)),
                  ),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: Text(
                  '$sets',
                  textAlign: TextAlign.right,
                  style: AppText.tabular(
                    AppText.label.copyWith(color: kInk, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _VolumeBar(sets: sets, progress: progress, scale: scale, band: band),
        ],
      ),
    );
  }
}

/// A slim bar of this week's sets over a shaded band for the evidence range.
class _VolumeBar extends StatelessWidget {
  const _VolumeBar({
    required this.sets,
    required this.progress,
    required this.scale,
    required this.band,
  });

  final int sets;
  final TrainingProgress progress;
  final int scale;
  final VolumeBand band;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    final fill = switch (band) {
      VolumeBand.inRange => accent.fill,
      VolumeBand.over => kFlame,
      _ => kInkMuted,
    };
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double x(int v) => w * (v / scale).clamp(0.0, 1.0);
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Positioned(
                left: x(progress.rangeMin),
                width: x(progress.rangeMax) - x(progress.rangeMin),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.fill.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (sets > 0)
                Positioned(
                  left: 0,
                  width: x(sets),
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
