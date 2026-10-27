import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/cached_resource.dart';
import '../../state/insights.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import 'insight_charts.dart';
import 'insights_logic.dart';

/// A page whose content needs one or more cached reads. It shows a skeleton until every read has
/// a value, an error with a retry when one failed with nothing to show, and the offline strip
/// when any value comes from the cache. Opening it also refreshes the insights, so a figure
/// synced a moment ago is not served from the last visit.
class InsightsFrame extends ConsumerStatefulWidget {
  const InsightsFrame({
    super.key,
    required this.title,
    required this.sources,
    required this.onRetry,
    required this.builder,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<AsyncValue<Cached<Object?>>> sources;
  final Future<void> Function() onRetry;
  final List<Widget> Function(BuildContext context) builder;

  @override
  ConsumerState<InsightsFrame> createState() => _InsightsFrameState();
}

class _InsightsFrameState extends ConsumerState<InsightsFrame> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(insightsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final held = [
      for (final s in widget.sources)
        if (s.value case final v? when v.userId == userId) v,
    ];
    if (held.length < widget.sources.length) {
      final failed = widget.sources.where((s) => s.hasError).firstOrNull;
      return PageScaffold(
        title: widget.title,
        subtitle: widget.subtitle,
        children: [
          if (failed != null)
            ErrorBlock(
              title: 'Could not load ${widget.title.toLowerCase()}',
              error: failed.error!,
              onRetry: widget.onRetry,
            )
          else
            const _Skeleton(),
        ],
      );
    }
    final offline = held.map((h) => h.offline).whereType<OfflineInfo>().firstOrNull;
    return PageScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      banner: offline == null ? null : OfflineBanner(info: offline),
      children: widget.builder(context),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBlock(height: 120, radius: 16),
        SizedBox(height: kCardGap),
        SkeletonBlock(height: 220, radius: 16),
        SizedBox(height: kCardGap),
        SkeletonBlock(height: 90, radius: 16),
      ],
    ),
  );
}

/// A small card with a caption above a bold value, for the averages grids.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label, $value${note == null ? '' : ', $note'}',
    excludeSemantics: true,
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption.copyWith(color: kInkSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppText.tabular(AppText.headline.copyWith(fontWeight: FontWeight.w900)),
          ),
          if (note != null) ...[const SizedBox(height: 2), Text(note!, style: AppText.caption)],
        ],
      ),
    ),
  );
}

/// Two [StatCard]s side by side that stack on a narrow or large-text layout.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (scale > 1.6 || box.maxWidth < 260) {
        return Column(
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(height: kCardGap),
              SizedBox(width: double.infinity, child: c),
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(width: kCardGap),
              Expanded(child: c),
            ],
          ],
        ),
      );
    },
  );
}

/// A tinted circle holding an icon.
class IconDisc extends StatelessWidget {
  const IconDisc({super.key, required this.icon, required this.palette, this.size = 44});

  final IconData icon;
  final AccentPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
    child: Icon(icon, size: size * 0.54, color: palette.lip),
  );
}

/// Deep, core, REM and awake with their minutes under a [StageBar].
class StageLegend extends StatelessWidget {
  const StageLegend({super.key, required this.stages, required this.label});

  final Map<SleepStage, int> stages;
  final String Function(int minutes) label;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final s in SleepStage.values)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: sleepStageColor(s), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${sleepStageName(s)} ${label(stages[s] ?? 0)}',
                style: AppText.label.copyWith(color: kInkSecondary),
              ),
            ),
          ],
        ),
    ],
  );
}
