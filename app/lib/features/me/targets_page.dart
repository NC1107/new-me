import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/targets.dart';
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
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../setup/about_you.dart';
import '../setup/about_you_page.dart';
import 'apple_health_page.dart';
import 'me_support.dart';
import 'target_card.dart';
import 'targets_logic.dart';

/// Research-backed targets (docs/design-v8.md): each with its formula, label and sources, and a
/// way to make it the setting in force from tomorrow.
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
              ]),
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
        await showLogSheet(context, kind: LogKind.pushups, maxTest: true);
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
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MissingCard(items: missing, onFix: _fix, enabled: offline == null),
        ],
        if (usableTargets.isNotEmpty) ...[
          const SizedBox(height: 16),
          if (_error != null) SaveError(_error!),
          ChunkyButton(
            label: 'Use all (${usableTargets.length})',
            busy: _busy.length > 1,
            onPressed: offline == null && _busy.isEmpty ? () => _apply(usableTargets) : null,
          ),
          const SizedBox(height: 6),
          const Text('Changes start tomorrow.', style: AppText.caption),
        ] else if (_error != null) ...[
          const SizedBox(height: 16),
          SaveError(_error!),
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
    return [
      const SizedBox(height: 24),
      Semantics(header: true, child: Text(group.title, style: AppText.headline)),
      const SizedBox(height: 10),
      for (final (i, t) in targets.indexed) ...[
        if (i > 0) const SizedBox(height: kCardGap),
        TargetCard(
          target: t,
          report: report,
          estimate: t.key == 'maintenance' && estimate?.value != null ? estimate : null,
          busy: !enabled || _busy.isNotEmpty,
          onUse: () => _apply([t]),
          onMaxTest: () => _fix(kPushupMaxItem),
        ),
      ],
    ];
  }
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
          child: Text('Needed to work these out', style: AppText.headline.copyWith(fontSize: 17)),
        ),
        const SizedBox(height: 2),
        const Text('Nothing is guessed.', style: AppText.caption),
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
