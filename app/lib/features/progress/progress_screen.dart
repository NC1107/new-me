import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/v7.dart';
import '../../util/people.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import '../me/settings_row.dart';
import '../training/training_progress_page.dart';
import 'lookback_screen.dart';
import 'metric_card.dart';
import 'milestones_page.dart';
import 'progress_logic.dart';
import 'units_view.dart';
import '../../widgets/units_scope.dart';

const kProgressWindow = 30;

/// Opens Progress from Insights or Us.
Future<void> openProgress(BuildContext context) => pushPage(context, const ProgressScreen());

/// The long run: every metric against the 30 days before it and against the first 30 days, for
/// you or your partner.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressProvider(kProgressWindow));
    final myId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    return PageScaffold(
      title: 'Progress',
      subtitle: 'How you are moving over the long run',
      children: [
        ...progress.when(
          data: (data) => _loaded(context, data, myId),
          error: (e, _) => [
            ErrorBlock(
              title: 'Could not load progress',
              error: e,
              onRetry: () async => ref.invalidate(progressProvider(kProgressWindow)),
            ),
          ],
          loading: () => const [_ProgressSkeleton()],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.calendar_month_rounded,
              palette: accentById('violet'),
              title: 'Monthly look-back',
              subtitle: 'The month against the one before',
              onTap: () => pushPage(context, const LookbackScreen()),
            ),
            SettingsRow(
              icon: Icons.fitness_center_rounded,
              palette: accentById('rose'),
              title: 'Weekly sets',
              subtitle: 'Training volume per muscle against the evidence',
              onTap: () => pushPage(context, const TrainingProgressPage()),
            ),
            SettingsRow(
              icon: Icons.emoji_events_rounded,
              palette: accentById('amber'),
              title: 'Milestones',
              subtitle: 'Streaks and firsts you have earned',
              onTap: () => pushPage(context, const MilestonesPage()),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _loaded(BuildContext context, Progress data, int? myId) {
    if (data.people.isEmpty) {
      return [Text('Nothing to compare yet.', style: AppText.body.copyWith(color: kInkSecondary))];
    }
    final people = meFirst(data.people, myId, (p) => p.userId);
    final person = people.where((p) => p.userId == (_selected ?? myId)).firstOrNull ?? people.first;
    final palette = accentById(person.color);
    final units = context.units;
    final metrics = orderedMetrics([
      for (final m in person.metrics)
        if (metricHasData(m)) metricInUnits(m, units),
    ]);
    return [
      if (data.people.length > 1) ...[
        _PersonSwitcher(
          people: people,
          selected: person.userId,
          onChanged: (id) => setState(() => _selected = id),
        ),
        const SizedBox(height: 16),
      ],
      if (metrics.isEmpty)
        Text('Nothing to show yet.', style: AppText.body.copyWith(color: kInkSecondary))
      else if (metrics.any(metricIsSparse)) ...[
        const Text(
          'Trends show after a second week, and comparisons once there is a full month.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
      ],
      for (final (i, m) in metrics.indexed) ...[
        if (i > 0) const SizedBox(height: kCardGap),
        MetricCard(metric: m, window: data.window, color: palette.fill),
      ],
    ];
  }
}

/// Two person chips; the chosen one is tinted in their colour.
class _PersonSwitcher extends StatelessWidget {
  const _PersonSwitcher({required this.people, required this.selected, required this.onChanged});

  final List<PersonProgress> people;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, p) in people.indexed) ...[
        if (i > 0) const SizedBox(width: kCardGap),
        Expanded(
          child: _PersonChip(person: p, on: p.userId == selected, onTap: () => onChanged(p.userId)),
        ),
      ],
    ],
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person, required this.on, required this.onTap});

  final PersonProgress person;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(person.color);
    return Semantics(
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      label: person.name,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: on ? null : onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kMotionDuration,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? palette.tint : kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: on ? palette.fill : kBorder, width: kBorderWidth),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Avatar(name: person.name, palette: palette, size: 32),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: on ? palette.lip : kInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: kCardGap),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.all(Radius.circular(kRadiusCard)),
            border: Border.fromBorderSide(BorderSide(color: kBorder, width: kBorderWidth)),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBlock(width: 120, height: 20),
                SizedBox(height: 14),
                SkeletonBlock(width: 80, height: 32),
                SizedBox(height: 14),
                SkeletonBlock(height: 48),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}
