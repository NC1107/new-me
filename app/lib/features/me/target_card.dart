import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dialogs.dart';
import '../log/log_chip.dart';
import 'targets_logic.dart';

/// One target at a glance: the value, whether it is in use, and Use this when the setting differs.
/// How it is worked out lives behind the info button.
class TargetCard extends StatelessWidget {
  const TargetCard({
    super.key,
    required this.target,
    required this.report,
    required this.busy,
    required this.onUse,
    required this.onMaxTest,
    this.estimate,
  });

  final Target target;
  final TargetsReport report;

  /// The log-based estimate, shown under maintenance when the server could compute it.
  final Target? estimate;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback onMaxTest;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final value = t.value;
    final name = targetName(t.key);
    final differs = t.applicable && !t.isApplied && t.current != null;
    final maxTest = t.missing.contains('pushupMax');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(name, style: AppText.headline.copyWith(fontSize: 17)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline_rounded, size: 20),
                color: kInkMuted,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: 'How $name is worked out',
                onPressed: () => showAppSheet<void>(
                  context,
                  builder: (_) => _HowSheet(target: t, report: report, estimate: estimate),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Flexible(
                  child: value != null
                      ? Text(
                          formatTargetValue(value, t.unit),
                          style: AppText.tabular(AppText.title.copyWith(fontSize: 26)),
                        )
                      : Text('Not available yet', style: AppText.body.copyWith(color: kInkMuted)),
                ),
                if (t.isApplied && t.applicable) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: kSuccess,
                    semanticLabel: 'In use',
                  ),
                ],
              ],
            ),
          ),
          if (differs || t.canUse || maxTest) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (t.canUse)
                    LogChip(
                      label: 'Use this',
                      selected: true,
                      enabled: !busy,
                      semanticLabel: 'Use this ${name.toLowerCase()} target',
                      onTap: onUse,
                    ),
                  if (maxTest)
                    LogChip(
                      label: 'Max test',
                      onTap: onMaxTest,
                      semanticLabel: 'Record a max test',
                    ),
                  if (differs)
                    Text(
                      'Yours: ${formatTargetValue(t.current!, t.unit)}',
                      style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowSheet extends StatelessWidget {
  const _HowSheet({required this.target, required this.report, this.estimate});

  final Target target;
  final TargetsReport report;
  final Target? estimate;

  @override
  Widget build(BuildContext context) {
    final t = target;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(targetName(t.key), style: AppText.title),
              LabelChip(label: t.label),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.formula, style: AppText.body),
          for (final line in detailLines(t)) ...[
            const SizedBox(height: 8),
            Text(line, style: AppText.label.copyWith(color: kInkSecondary)),
          ],
          if (estimate case final e?) ...[
            const SizedBox(height: 16),
            Text(
              '${targetName(e.key)}: ${formatTargetValue(e.value!, e.unit)}',
              style: AppText.tabular(AppText.headline.copyWith(fontSize: 17)),
            ),
            const SizedBox(height: 4),
            Text(e.formula, style: AppText.label.copyWith(color: kInkSecondary)),
          ],
          _Citations(keys: {...t.sources, ...?estimate?.sources}.toList(), report: report),
        ],
      ),
    );
  }
}

class _Citations extends StatelessWidget {
  const _Citations({required this.keys, required this.report});

  final List<String> keys;
  final TargetsReport report;

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(keys.length == 1 ? 'Source' : 'Sources', style: AppText.headline),
        ),
        for (final key in keys) ...[
          const SizedBox(height: 8),
          Text(report.citation(key), style: AppText.caption),
        ],
      ],
    );
  }
}

/// "Convention", "Guideline" or "Derivation". The icon repeats the word so colour is never the
/// only signal.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label});

  final TargetLabel label;

  @override
  Widget build(BuildContext context) {
    final icon = switch (label) {
      TargetLabel.guideline => Icons.menu_book_rounded,
      TargetLabel.convention => Icons.rule_rounded,
      TargetLabel.derivation => Icons.functions_rounded,
    };
    return Semantics(
      label: 'Label: ${label.title}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: kBorder, width: kBorderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kInkSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
