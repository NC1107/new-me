import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../log/log_chip.dart';
import 'targets_logic.dart';

/// How one target is worked out: its figure beside the person's own setting, the plain reason,
/// the formula and the sources. [onUse] and [onMaxTest] close the sheet before they run.
Future<void> showTargetSheet(
  BuildContext context, {
  required Target target,
  required TargetsReport report,
  required bool hasYours,
  required bool enabled,
  required VoidCallback onUse,
  required VoidCallback onMaxTest,
  Target? estimate,
  Units units = Units.metric,
}) => showAppSheet<void>(
  context,
  builder: (sheet) => _TargetSheet(
    target: target,
    report: report,
    estimate: estimate,
    hasYours: hasYours,
    enabled: enabled,
    units: units,
    onUse: () {
      Navigator.of(sheet).pop();
      onUse();
    },
    onMaxTest: () {
      Navigator.of(sheet).pop();
      onMaxTest();
    },
  ),
);

class _TargetSheet extends StatelessWidget {
  const _TargetSheet({
    required this.target,
    required this.report,
    required this.hasYours,
    required this.enabled,
    required this.units,
    required this.onUse,
    required this.onMaxTest,
    this.estimate,
  });

  final Target target;
  final TargetsReport report;
  final Target? estimate;
  final bool hasYours;
  final bool enabled;
  final Units units;
  final VoidCallback onUse;
  final VoidCallback onMaxTest;

  String _text(int v) => formatTargetValue(v, target.unit, units: units);

  @override
  Widget build(BuildContext context) {
    final t = target;
    final value = t.value;
    final setting = t.applicable && hasYours;
    final maxTest = t.missing.contains('pushupMax');
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
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (setting) ...[
                Expanded(
                  child: _Figure(
                    heading: 'Yours',
                    text: t.current == null ? 'Not set' : _text(t.current!),
                    muted: t.current == null,
                    inUse: t.isApplied,
                  ),
                ),
                const SizedBox(width: kCardGap),
              ],
              Expanded(
                child: _Figure(
                  heading: hasYours ? 'Recommended' : 'Estimate',
                  text: value == null ? 'Not yet' : _text(value),
                  muted: value == null,
                ),
              ),
            ],
          ),
          if (t.canUse || maxTest) ...[
            const SizedBox(height: 14),
            if (t.canUse)
              ChunkyButton(label: 'Use ${_text(value!)}', onPressed: enabled ? onUse : null),
            if (maxTest)
              Align(
                alignment: Alignment.centerLeft,
                child: LogChip(
                  label: 'Record a max test',
                  onTap: onMaxTest,
                  semanticLabel: 'Record a max test',
                ),
              ),
          ],
          if (t.why.isNotEmpty) ...[const SizedBox(height: 16), Text(t.why, style: AppText.body)],
          const SizedBox(height: 12),
          Text(t.formula, style: AppText.label.copyWith(color: kInkSecondary)),
          for (final line in detailLines(t)) ...[
            const SizedBox(height: 8),
            Text(line, style: AppText.label.copyWith(color: kInkSecondary)),
          ],
          if (t.alternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: const Text('Other published figures', style: AppText.headline),
            ),
            for (final a in t.alternatives) ...[
              const SizedBox(height: 6),
              Text(
                '${_text(a.value)}: ${a.label}',
                style: AppText.label.copyWith(color: kInkSecondary),
              ),
            ],
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

class _Figure extends StatelessWidget {
  const _Figure({
    required this.heading,
    required this.text,
    this.muted = false,
    this.inUse = false,
  });

  final String heading;
  final String text;
  final bool muted;
  final bool inUse;

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: AppText.caption),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                text,
                style: AppText.tabular(
                  AppText.headline.copyWith(fontSize: 20, color: muted ? kInkMuted : kInk),
                ),
              ),
            ),
            if (inUse) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: kSuccess,
                semanticLabel: 'In use',
              ),
            ],
          ],
        ),
      ],
    ),
  );
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
