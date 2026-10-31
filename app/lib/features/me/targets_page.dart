import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/targets.dart';
import '../../state/units.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import '../setup/about_you.dart';
import '../setup/about_you_page.dart';
import 'apple_health_page.dart';
import 'daily_reps_page.dart';
import 'me_support.dart';
import 'target_row.dart';
import 'target_sheet.dart';
import 'targets_logic.dart';

/// Research-backed targets (docs/design-v8.md): each with its formula, label and sources, and a
/// way to make it the setting in force from today.
class TargetsPage extends ConsumerStatefulWidget {
  const TargetsPage({super.key});

  @override
  ConsumerState<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends ConsumerState<TargetsPage> {
  Set<String> _busy = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    // A held answer may predate a weigh-in or a profile edit made elsewhere.
    if (ref.exists(targetsProvider)) {
      Future.microtask(() {
        if (mounted) unawaited(ref.read(targetsProvider.notifier).refresh());
      });
    }
  }

  Future<void> _apply(List<Target> targets) async {
    if (_busy.isNotEmpty || targets.isEmpty) return;
    setState(() {
      _busy = {for (final t in targets) t.key};
      _error = null;
    });
    try {
      final applied = await ref.read(targetsProvider.notifier).apply([
        for (final t in targets) t.key,
      ]);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              appliedToast([
                for (final t in targets)
                  if (applied.contains(t.key)) t,
              ], units: ref.read(unitsProvider)),
            ),
          ),
        );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = {});
    }
  }

  Future<void> _fix(MissingItem item) async {
    switch (item.fix) {
      case FixAt.aboutYou:
        await pushPage(context, AboutYouPage(start: item.question ?? AboutQuestion.birthYear));
      case FixAt.health:
        await pushPage(context, const AppleHealthPage());
      case FixAt.pushupMax:
        await pushPage(context, const DailyRepsPage());
    }
    if (mounted) unawaited(ref.read(targetsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(targetsProvider);
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final held = value.value;
    final cached = held != null && held.userId == userId ? held : null;
    if (cached == null) {
      return PageScaffold(
        title: 'Targets',
        children: [
          if (value.hasError)
            ErrorBlock(
              title: 'Could not load your targets',
              error: value.error!,
              onRetry: ref.read(targetsProvider.notifier).refresh,
            )
          else
            const _Skeleton(),
        ],
      );
    }
    final report = cached.data;
    final offline = cached.offline;
    final missing = missingItems(report);
    final usableTargets = usable(report);
    final estimate = report.target(kEstimateKey);
    return PageScaffold(
      title: 'Targets',
      banner: offline == null ? null : OfflineBanner(info: offline),
      children: [
        if (report.disclaimer.isNotEmpty)
          Text(
            report.disclaimer,
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
        if (value.hasError) ...[
          const SizedBox(height: 12),
          ErrorBlock(
            title: 'Could not refresh your targets',
            error: value.error!,
            onRetry: ref.read(targetsProvider.notifier).refresh,
          ),
        ],
        if (usableTargets.isNotEmpty || _error != null) ...[
          const SizedBox(height: 16),
          if (_error != null) SaveError(_error!),
          if (usableTargets.isNotEmpty)
            _UseAllCard(
              count: usableTargets.length,
              busy: _busy.length > 1,
              onUse: offline == null && _busy.isEmpty ? () => _apply(usableTargets) : null,
            ),
        ] else if (report.targets.any((t) => t.isApplied && t.applicable)) ...[
          const SizedBox(height: 16),
          const _AllMatchNote(),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MissingCard(items: missing, onFix: _fix, enabled: offline == null),
        ],
        for (final group in kTargetGroups)
          ..._group(group, report, estimate, enabled: offline == null),
      ],
    );
  }

  List<Widget> _group(
    TargetGroup group,
    TargetsReport report,
    Target? estimate, {
    required bool enabled,
  }) {
    final targets = [for (final key in group.keys) ?report.target(key)];
    if (targets.isEmpty) return const [];
    final units = ref.watch(unitsProvider);
    return [
      const SizedBox(height: 24),
      Semantics(header: true, child: Text(group.title, style: AppText.headline)),
      const SizedBox(height: 8),
      TargetColumnHeads(hasYours: group.hasYours),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, t) in targets.indexed) ...[
              if (i > 0) const Divider(height: 0, thickness: kBorderWidth, color: kBorder),
              TargetRow(
                target: t,
                hasYours: group.hasYours,
                units: units,
                onTap: () => showTargetSheet(
                  context,
                  target: t,
                  report: report,
                  estimate: t.key == 'maintenance' && estimate?.value != null ? estimate : null,
                  hasYours: group.hasYours,
                  enabled: enabled && _busy.isEmpty,
                  units: units,
                  onUse: () => _apply([t]),
                  onMaxTest: () => _fix(kPushupMaxItem),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _UseAllCard extends StatelessWidget {
  const _UseAllCard({required this.count, required this.busy, required this.onUse});

  final int count;
  final bool busy;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChunkyButton(label: 'Use all recommended ($count)', busy: busy, onPressed: onUse),
      const SizedBox(height: 6),
      const Text(
        'Sets your goals to the recommended figures. Changes apply today.',
        style: AppText.caption,
      ),
    ],
  );
}

class _AllMatchNote extends StatelessWidget {
  const _AllMatchNote();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.check_circle_rounded, size: 20, color: kSuccess),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Your goals match the recommendations.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _MissingCard extends StatelessWidget {
  const _MissingCard({required this.items, required this.onFix, required this.enabled});

  final List<MissingItem> items;
  final void Function(MissingItem item) onFix;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Add these to work out your targets',
            style: AppText.headline.copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: '${item.label}. ${item.hint}',
            onTap: () => onFix(item),
            child: Pressable(
              scale: 0.99,
              onTap: () => onFix(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label, style: AppText.body),
                            Text(item.hint, style: AppText.caption),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: kInkMuted),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBlock(height: 24, radius: 8),
        SizedBox(height: kCardGap),
        SkeletonBlock(height: 160, radius: 16),
        SizedBox(height: kCardGap),
        SkeletonBlock(height: 160, radius: 16),
      ],
    ),
  );
}
