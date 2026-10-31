import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/pressable.dart';
import 'targets_logic.dart';

/// Widths of the two number columns, so every row of a section lines up under its headings.
const kYoursWidth = 92.0;
const kRecommendedWidth = 104.0;

/// Large text has no room for two number columns, so each row stacks its figures under its name.
bool stackedTargets(BuildContext context) => MediaQuery.textScalerOf(context).scale(15) > 20;

/// The headings above a section's rows.
class TargetColumnHeads extends StatelessWidget {
  const TargetColumnHeads({super.key, required this.hasYours});

  final bool hasYours;

  @override
  Widget build(BuildContext context) {
    if (stackedTargets(context)) return const SizedBox.shrink();
    final style = AppText.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w700);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14 + 20, 6),
        child: Row(
          children: [
            const Spacer(),
            if (hasYours)
              SizedBox(
                width: kYoursWidth,
                child: Text('Yours', style: style),
              ),
            SizedBox(
              width: kRecommendedWidth,
              child: Text(hasYours ? 'Recommended' : 'Estimate', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// One target as a compact row: its name, the person's own setting and the recommendation side
/// by side. How it is worked out waits behind a tap.
class TargetRow extends StatelessWidget {
  const TargetRow({
    super.key,
    required this.target,
    required this.hasYours,
    required this.onTap,
    this.units = Units.metric,
  });

  final Target target;
  final bool hasYours;
  final VoidCallback onTap;
  final Units units;

  String? get _yours {
    final current = target.current;
    return current == null ? null : formatTargetValue(current, target.unit, units: units);
  }

  String? get _recommended {
    final value = target.value;
    return value == null ? null : formatTargetValue(value, target.unit, units: units);
  }

  @override
  Widget build(BuildContext context) {
    final t = target;
    final name = targetName(t.key);
    final setting = t.applicable && hasYours;
    final spoken = StringBuffer(name);
    if (setting) spoken.write('. Yours ${_yours ?? 'not set'}');
    spoken.write(
      '. ${hasYours ? 'Recommended' : 'Estimate'} ${_recommended ?? 'not yet available'}',
    );
    if (t.canUse) spoken.write('. Differs from yours');
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: spoken.toString(),
      hint: 'How it is worked out',
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: stackedTargets(context)
                ? _stacked(name, setting)
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (hasYours)
                        SizedBox(
                          width: kYoursWidth,
                          child: setting
                              ? _Yours(text: _yours, applied: t.isApplied)
                              : const _Dash(),
                        ),
                      SizedBox(
                        width: kRecommendedWidth,
                        child: _Recommended(text: _recommended, highlight: t.canUse),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: kInkMuted),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

extension on TargetRow {
  Widget _stacked(String name, bool setting) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Wrap(
              spacing: 16,
              runSpacing: 2,
              children: [
                if (setting) _Labeled('Yours', _Yours(text: _yours, applied: target.isApplied)),
                _Labeled(
                  hasYours ? 'Recommended' : 'Estimate',
                  _Recommended(text: _recommended, highlight: target.canUse),
                ),
              ],
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right_rounded, size: 20, color: kInkMuted),
    ],
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AppText.caption),
      child,
    ],
  );
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) => Text('-', style: AppText.body.copyWith(color: kInkMuted));
}

class _Yours extends StatelessWidget {
  const _Yours({required this.text, required this.applied});

  final String? text;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return Text('Not set', style: AppText.label.copyWith(color: kInkMuted));
    }
    return Row(
      children: [
        Flexible(child: Text(text!, style: AppText.tabular(AppText.label.copyWith(fontSize: 15)))),
        if (applied) ...[
          const SizedBox(width: 3),
          const Icon(Icons.check_rounded, size: 16, color: kSuccess, semanticLabel: 'In use'),
        ],
      ],
    );
  }
}

class _Recommended extends StatelessWidget {
  const _Recommended({required this.text, required this.highlight});

  final String? text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return Text('Not yet', style: AppText.label.copyWith(color: kInkMuted));
    }
    final person = context.accentPalette;
    final label = Text(
      text!,
      style: AppText.tabular(
        AppText.label.copyWith(fontSize: 15, color: highlight ? person.lip : kInk),
      ),
    );
    if (!highlight) return label;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(color: person.tint, borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: label,
        ),
      ),
    );
  }
}
