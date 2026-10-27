import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../log/log_chip.dart';
import 'targets_logic.dart';

/// One target: value and unit, the setting in force, the formula sentence, how firmly it rests
/// on a source, and the citations behind it.
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
    final lines = detailLines(t);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(targetName(t.key), style: AppText.headline.copyWith(fontSize: 17)),
              ),
              LabelChip(label: t.label),
            ],
          ),
          const SizedBox(height: 6),
          if (value != null)
            Text(
              formatTargetValue(value, t.unit),
              style: AppText.tabular(AppText.title.copyWith(fontSize: 26)),
            )
          else
            Text('Not available yet', style: AppText.body.copyWith(color: kInkMuted)),
          if (t.applicable) ...[
            const SizedBox(height: 2),
            Text(
              t.current == null
                  ? 'Your setting: not set'
                  : 'Your setting: ${formatTargetValue(t.current!, t.unit)}',
              style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            t.formula,
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
          for (final line in lines) ...[
            const SizedBox(height: 6),
            Text(line, style: AppText.caption),
          ],
          SourcesLine(target: t, report: report),
          if (estimate case final e?) ...[
            const SizedBox(height: 4),
            _EstimateLine(estimate: e, report: report),
          ],
          if (t.canUse || t.missing.contains('pushupMax') || (t.isApplied && t.applicable)) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (t.canUse)
                  LogChip(
                    label: 'Use this',
                    selected: true,
                    enabled: !busy,
                    semanticLabel: 'Use this ${targetName(t.key).toLowerCase()} target',
                    onTap: onUse,
                  ),
                if (t.missing.contains('pushupMax'))
                  LogChip(label: 'Max test', onTap: onMaxTest, semanticLabel: 'Record a max test'),
                if (t.isApplied) const _InUse(),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InUse extends StatelessWidget {
  const _InUse();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, size: 18, color: kSuccess),
        const SizedBox(width: 6),
        Text('In use', style: AppText.label.copyWith(color: kInkSecondary)),
      ],
    ),
  );
}

class _EstimateLine extends StatelessWidget {
  const _EstimateLine({required this.estimate, required this.report});

  final Target estimate;
  final TargetsReport report;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(kRadiusField)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${targetName(estimate.key)}: ${formatTargetValue(estimate.value!, estimate.unit)}',
              style: AppText.tabular(AppText.label),
            ),
            LabelChip(label: estimate.label),
          ],
        ),
        const SizedBox(height: 4),
        Text(estimate.formula, style: AppText.caption),
        SourcesLine(target: estimate, report: report),
      ],
    ),
  );
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

/// An expandable line that lists the full citation of every source a target rests on.
class SourcesLine extends StatefulWidget {
  const SourcesLine({super.key, required this.target, required this.report});

  final Target target;
  final TargetsReport report;

  @override
  State<SourcesLine> createState() => _SourcesLineState();
}

class _SourcesLineState extends State<SourcesLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final keys = widget.target.sources;
    if (keys.isEmpty) return const SizedBox.shrink();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final label = keys.length == 1 ? 'Source' : 'Sources (${keys.length})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          expanded: _open,
          label: '$label for ${targetName(widget.target.key)}',
          excludeSemantics: true,
          onTap: () => setState(() => _open = !_open),
          child: Pressable(
            haptic: false,
            scale: 0.99,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Flexible(
                    child: Text(label, style: AppText.label.copyWith(color: context.accentText)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 22,
                    color: context.accentText,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: reduce ? Duration.zero : kMotionDuration,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final key in keys)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('- ', style: AppText.caption),
                              Expanded(
                                child: Text(widget.report.citation(key), style: AppText.caption),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
